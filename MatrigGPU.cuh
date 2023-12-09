#pragma once

#include <Eigen/Core>
#include <thrust/device_vector.h>
#include <magma_v2.h>
#include <iostream>

namespace std {
	float  real(magmaFloatComplex z) { return z.x; }
	double real(magmaDoubleComplex z) { return z.x; }
}  // namespace std

namespace GPU {
	class MAGMA {
		private:
			MAGMA() { magma_init(); }
			~MAGMA() { magma_finalize(); }

		public:
			MAGMA(const MAGMA&)            = delete;
			MAGMA& operator=(const MAGMA&) = delete;
			MAGMA(MAGMA&&)                 = delete;
			MAGMA& operator=(MAGMA&&)      = delete;

			static MAGMA& get_contoroller() {
				static MAGMA instance;
				return instance;
			}
	};

	template<typename Scalar_>
	struct traits {
			using Scalar = Scalar_;
	};
	template<>
	struct traits<std::complex<float>> {
			using Scalar = magmaFloatComplex;
	};
	template<>
	struct traits<std::complex<double>> {
			using Scalar = magmaDoubleComplex;
	};

	template<class MatrixCPU>
	class MatrixGPU;

	template<typename Scalar_, int Rows_, int Cols_, int Options_, int MaxRows_, int MaxCols_>
	class MatrixGPU<Eigen::Matrix<Scalar_, Rows_, Cols_, Options_, MaxRows_, MaxCols_>> {
		public:
			using MatrixCPU  = Eigen::Matrix<Scalar_, Rows_, Cols_, Options_, MaxRows_, MaxCols_>;
			using Index      = magma_int_t;
			using Scalar     = typename traits<typename MatrixCPU::Scalar>::Scalar;
			using RealScalar = typename MatrixCPU::RealScalar;
			enum {
				RowsAtCompileTime        = Rows_,
				ColsAtCompileTime        = Cols_,
				MaxRowsAtCompileTime     = MaxRows_,
				MaxColsAtCompileTime     = MaxCols_,
				Options                  = Options_,
				InnerStrideAtCompileTime = 1,
				OuterStrideAtCompileTime
				= (Options & Eigen::RowMajor) ? ColsAtCompileTime : RowsAtCompileTime
			};
			enum { IsVectorAtCompileTime = (RowsAtCompileTime == 1) || (ColsAtCompileTime == 1) };

		private:
			static constexpr int          alingment = 32;
			Index                         m_rows    = RowsAtCompileTime;
			Index                         m_cols    = ColsAtCompileTime;
			Index                         m_LD      = 0;
			thrust::device_vector<Scalar> m_data;

		public:
			// Default constructor
			MatrixGPU(Index rows = RowsAtCompileTime, Index cols = ColsAtCompileTime)
			    : m_rows{rows}, m_cols{cols} {
				this->resize(rows, cols);
			}
			// Copy constructor
			MatrixGPU(MatrixGPU const& other) = default;
			// Copy assignment operator
			MatrixGPU& operator=(MatrixGPU const& other) = default;
			// Move constructor
			MatrixGPU(MatrixGPU&& other) = default;
			// Move assignment operator
			MatrixGPU& operator=(MatrixGPU&& other) = default;

			// Custom constructor
			MatrixGPU(MatrixCPU const& mat) : MatrixGPU(mat.rows(), mat.cols()) {
				magma_queue_t queue = NULL;
				magma_queue_create(0, &queue);
				magma_setmatrix(mat.rows(), mat.cols(), sizeof(Scalar), mat.data(), mat.rows(),
				                this->data(), m_LD, queue);
				magma_queue_destroy(queue);
			}

		public:
			Index         rows() const { return m_rows; }
			Index         cols() const { return m_cols; }
			Index         LD() const { return m_LD; }
			Index         size() const { return m_data.size(); }
			Scalar*       data() { return m_data.data().get(); }
			Scalar const* data() const { return m_data.data().get(); }
			void          resize(Index rows, Index cols) {
                m_rows = rows;
                m_cols = cols;
                m_LD   = magma_roundup(rows, alingment);
                m_data.resize(m_LD * m_cols);
			};
			void resize(Index size) {
				static_assert(IsVectorAtCompileTime);
				if constexpr(RowsAtCompileTime == 1) { m_cols = size; }
				else { m_rows = size; }
				m_LD = size;
				m_data.resize(size);
			}

			void copyTo(MatrixCPU& res) const {
				res.resize(m_rows, m_cols);
				magma_queue_t queue = NULL;
				magma_queue_create(0, &queue);
				magma_getmatrix(res.rows(), res.cols(), sizeof(Scalar), this->data(), m_LD,
				                res.data(), res.rows(), queue);
				magma_queue_destroy(queue);
			}

			friend std::ostream& operator<<(std::ostream& os, MatrixGPU const& dmat) {
				MatrixCPU res;
				dmat.copyTo(res);
				os << res << std::endl;
				return os;
			};
	};

	using Eigen::Dynamic;
#define EIGEN_MAKE_TYPEDEFS(Type, TypeSuffix, Size, SizeSuffix)                           \
	/** \ingroup matrixtypedefs */                                                        \
	typedef MatrixGPU<Eigen::Matrix<Type, Size, Size>> MatrixGPU##SizeSuffix##TypeSuffix; \
	/** \ingroup matrixtypedefs */                                                        \
	typedef MatrixGPU<Eigen::Matrix<Type, Size, 1>> VectorGPU##SizeSuffix##TypeSuffix;    \
	/** \ingroup matrixtypedefs */                                                        \
	typedef MatrixGPU<Eigen::Matrix<Type, 1, Size>> RowVectorGPU##SizeSuffix##TypeSuffix;

#define EIGEN_MAKE_FIXED_TYPEDEFS(Type, TypeSuffix, Size)                                 \
	/** \ingroup matrixtypedefs */                                                        \
	typedef MatrixGPU<Eigen::Matrix<Type, Size, Dynamic>> MatrixGPU##Size##X##TypeSuffix; \
	/** \ingroup matrixtypedefs */                                                        \
	typedef MatrixGPU<Eigen::Matrix<Type, Dynamic, Size>> MatrixGPU##X##Size##TypeSuffix;

#define EIGEN_MAKE_TYPEDEFS_ALL_SIZES(Type, TypeSuffix) \
	EIGEN_MAKE_TYPEDEFS(Type, TypeSuffix, 2, 2)         \
	EIGEN_MAKE_TYPEDEFS(Type, TypeSuffix, 3, 3)         \
	EIGEN_MAKE_TYPEDEFS(Type, TypeSuffix, 4, 4)         \
	EIGEN_MAKE_TYPEDEFS(Type, TypeSuffix, Dynamic, X)   \
	EIGEN_MAKE_FIXED_TYPEDEFS(Type, TypeSuffix, 2)      \
	EIGEN_MAKE_FIXED_TYPEDEFS(Type, TypeSuffix, 3)      \
	EIGEN_MAKE_FIXED_TYPEDEFS(Type, TypeSuffix, 4)

	EIGEN_MAKE_TYPEDEFS_ALL_SIZES(int, i)
	EIGEN_MAKE_TYPEDEFS_ALL_SIZES(float, f)
	EIGEN_MAKE_TYPEDEFS_ALL_SIZES(double, d)
	EIGEN_MAKE_TYPEDEFS_ALL_SIZES(std::complex<float>, cf)
	EIGEN_MAKE_TYPEDEFS_ALL_SIZES(std::complex<double>, cd)

#undef EIGEN_MAKE_TYPEDEFS_ALL_SIZES
#undef EIGEN_MAKE_TYPEDEFS
#undef EIGEN_MAKE_FIXED_TYPEDEFS

#if EIGEN_HAS_CXX11

	#define EIGEN_MAKE_TYPEDEFS(Size, SizeSuffix)                                 \
		/** \ingroup matrixtypedefs */                                            \
		/** \brief \cpp11 */                                                      \
		template<typename Type>                                                   \
		using MatrixGPU##SizeSuffix = MatrixGPU<Eigen::Matrix<Type, Size, Size>>; \
		/** \ingroup matrixtypedefs */                                            \
		/** \brief \cpp11 */                                                      \
		template<typename Type>                                                   \
		using VectorGPU##SizeSuffix = MatrixGPU<Eigen::Matrix<Type, Size, 1>>;    \
		/** \ingroup matrixtypedefs */                                            \
		/** \brief \cpp11 */                                                      \
		template<typename Type>                                                   \
		using RowVectorGPU##SizeSuffix = MatrixGPU<Eigen::Matrix<Type, 1, Size>>;

	#define EIGEN_MAKE_FIXED_TYPEDEFS(Size)                                       \
		/** \ingroup matrixtypedefs */                                            \
		/** \brief \cpp11 */                                                      \
		template<typename Type>                                                   \
		using MatrixGPU##Size##X = MatrixGPU<Eigen::Matrix<Type, Size, Dynamic>>; \
		/** \ingroup matrixtypedefs */                                            \
		/** \brief \cpp11 */                                                      \
		template<typename Type>                                                   \
		using MatrixGPU##X##Size = MatrixGPU<Eigen::Matrix<Type, Dynamic, Size>>;

	EIGEN_MAKE_TYPEDEFS(2, 2)
	EIGEN_MAKE_TYPEDEFS(3, 3)
	EIGEN_MAKE_TYPEDEFS(4, 4)
	EIGEN_MAKE_TYPEDEFS(Dynamic, X)
	EIGEN_MAKE_FIXED_TYPEDEFS(2)
	EIGEN_MAKE_FIXED_TYPEDEFS(3)
	EIGEN_MAKE_FIXED_TYPEDEFS(4)

	/** \ingroup matrixtypedefs
  * \brief \cpp11 */
	template<typename Type, int Size>
	using VectorGPU = MatrixGPU<Eigen::Matrix<Type, Size, 1>>;

	/** \ingroup matrixtypedefs
  * \brief \cpp11 */
	template<typename Type, int Size>
	using RowVectorGPU = MatrixGPU<Eigen::Matrix<Type, 1, Size>>;

	#undef EIGEN_MAKE_TYPEDEFS
	#undef EIGEN_MAKE_FIXED_TYPEDEFS

#endif  // EIGEN_HAS_CXX11

}  // namespace GPU