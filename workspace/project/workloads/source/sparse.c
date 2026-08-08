#define EXIT_SUCCESS 0

typedef unsigned long size_t;

// Forward declarations
void _start(void) __attribute__((naked, used));
void run_workload(void);
void sys_exit(int code);

// Memory region symbol defined by linker script/flags
extern char __ram;

// ==============================================================================
// 1. Core Entry Point & Bootstrap
// ==============================================================================
__attribute__((naked, used))
void _start(void) {
    __asm__ __volatile__(
        ".option push\n\t"
        ".option norvc\n\t"
        "la sp, __ram\n\t"           // Set stack pointer to RAM base
        "li t0, 0x00080000\n\t"       // Stack offset (512 KB)
        "add sp, sp, t0\n\t"
        "call run_workload\n\t"
        "li a0, 0\n\t"
        "tail sys_exit\n\t"
        ".option pop\n\t"
    );
}

// Compiler injects this for local array initialization
void* memcpy(void* dest, const void* src, size_t n) {
    char* d = (char*)dest;
    const char* s = (const char*)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dest;
}

// Reduced heap size to fit comfortably within the 512 KB RAM region (256 KB heap)
#define HEAP_SIZE (256 * 1024) 
static unsigned char heap[HEAP_SIZE];
static size_t heap_idx = 0;

void* my_calloc(size_t num, size_t size) {
    size_t total = num * size;
    total = (total + 7) & ~7; // Align to 8 bytes
    
    if (heap_idx + total > HEAP_SIZE) {
        return (void*)0; // Out of memory
    }
    
    void* ptr = &heap[heap_idx];
    heap_idx += total;
    
    char* cptr = (char*)ptr;
    for (size_t i = 0; i < total; i++) {
        cptr[i] = 0;
    }
    
    return ptr;
}

void my_free(void* ptr) {}

// RISC-V Linux-style exit syscall (Non-static for tail call visibility)
void sys_exit(int code) {
    register long a7 asm("a7") = 93; // sys_exit
    register long a0 asm("a0") = code;
    asm volatile ("ecall" : : "r"(a7), "r"(a0) : "memory");
    while (1) {} 
}

// -----------------------------------------------------------------------------
// 2. COO (Coordinate) Format
// -----------------------------------------------------------------------------

typedef struct Sparse_Coordinate {
    size_t n_rows;
    size_t n_cols;
    size_t nnz;
    size_t* row_indices;
    size_t* col_indices;
    double* values;
} Sparse_Coordinate;

int create_sparse_coordinate(
    const double* A, size_t n_rows, size_t n_cols, 
    size_t nnz, Sparse_Coordinate* A_coo
) {
    A_coo->n_rows = n_rows;
    A_coo->n_cols = n_cols;
    A_coo->nnz = nnz;
    
    A_coo->row_indices = (size_t*)my_calloc(nnz, sizeof(size_t));
    A_coo->col_indices = (size_t*)my_calloc(nnz, sizeof(size_t));
    A_coo->values = (double*)my_calloc(nnz, sizeof(double));

    size_t nnz_id = 0;
    for (size_t i = 0; i < n_rows; i++) {
        for (size_t j = 0; j < n_cols; j++) {
            if (A[i * n_cols + j] != 0) {
                A_coo->row_indices[nnz_id] = i;
                A_coo->col_indices[nnz_id] = j;
                A_coo->values[nnz_id] = A[i * n_cols + j];
                nnz_id++;
            }
        }
    }
    return EXIT_SUCCESS;
}

int matrix_vector_sparse_coordinate(
    const Sparse_Coordinate* A_coo, const double* vec, double* res
) {
    for (size_t i = 0; i < A_coo->n_rows; i++) {
        res[i] = 0.0;
    }
    for (size_t k = 0; k < A_coo->nnz; k++) {
        size_t row = A_coo->row_indices[k];
        size_t col = A_coo->col_indices[k];
        double val = A_coo->values[k];
        res[row] += val * vec[col];
    }
    return EXIT_SUCCESS;
}

int free_sparse_coordinate(Sparse_Coordinate* A_coo) {
    my_free(A_coo->row_indices);
    my_free(A_coo->col_indices);
    my_free(A_coo->values);
    return EXIT_SUCCESS;
}

// -----------------------------------------------------------------------------
// 3. CSR (Compressed Sparse Row) Format
// -----------------------------------------------------------------------------

typedef struct Sparse_CSR {
    size_t n_rows;
    size_t n_cols;
    size_t n_nz;
    size_t* row_ptr;
    size_t* col_indices;
    double* values;
} Sparse_CSR;

int create_sparse_csr(
    const double* A, size_t n_rows, size_t n_cols, 
    size_t n_nz, Sparse_CSR* A_csr
) {
    A_csr->n_rows = n_rows;
    A_csr->n_cols = n_cols;
    A_csr->n_nz = n_nz;
    
    A_csr->row_ptr = (size_t*)my_calloc(n_rows + 1, sizeof(size_t));
    A_csr->col_indices = (size_t*)my_calloc(n_nz, sizeof(size_t));
    A_csr->values = (double*)my_calloc(n_nz, sizeof(double));

    size_t nz_id = 0;
    for (size_t i = 0; i < n_rows; ++i) {
        A_csr->row_ptr[i] = nz_id;
        for (size_t j = 0; j < n_cols; ++j) {
            if (A[i * n_cols + j] != 0.0) {
                A_csr->col_indices[nz_id] = j;
                A_csr->values[nz_id] = A[i * n_cols + j];
                nz_id++;
            }
        }
    }
    A_csr->row_ptr[n_rows] = nz_id;
    return EXIT_SUCCESS;
}

int matrix_vector_sparse_csr(
    const Sparse_CSR* A_csr, const double* vec, double* res
) {
    for (size_t i = 0; i < A_csr->n_rows; ++i) {
        double sum = 0.0;
        size_t nz_start = A_csr->row_ptr[i];
        size_t nz_end = A_csr->row_ptr[i+1];
        
        for (size_t k = nz_start; k < nz_end; ++k) {
            size_t j = A_csr->col_indices[k];
            double val = A_csr->values[k];
            sum += val * vec[j];
        }
        res[i] = sum;
    }
    return EXIT_SUCCESS;
}

int free_sparse_csr(Sparse_CSR* A_csr) {
    my_free(A_csr->row_ptr);
    my_free(A_csr->col_indices);
    my_free(A_csr->values);
    return EXIT_SUCCESS;
}

// -----------------------------------------------------------------------------
// 4. Main Execution
// -----------------------------------------------------------------------------

void run_workload() {
    size_t n_rows = 5;
    size_t n_cols = 5;
    size_t nnz = 12;

    double A[] = {
        1,  0,  0,  2,  0,
        3,  4,  2,  5,  0,
        5,  0,  0,  8, 17,
        0,  0, 10, 16,  0,
        0,  0,  0,  0, 14
    };
    
    double x[] = { 1, 2, 3, 4, 5 };
    
    volatile double Ax_coo[5];
    volatile double Ax_csr[5];

    Sparse_Coordinate A_coo;
    create_sparse_coordinate(A, n_rows, n_cols, nnz, &A_coo);
    matrix_vector_sparse_coordinate(&A_coo, x, (double*)Ax_coo);
    free_sparse_coordinate(&A_coo);

    Sparse_CSR A_csr;
    create_sparse_csr(A, n_rows, n_cols, nnz, &A_csr);
    matrix_vector_sparse_csr(&A_csr, x, (double*)Ax_csr);
    free_sparse_csr(&A_csr);
}