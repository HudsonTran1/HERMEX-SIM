#include <math.h>

#ifndef SYS_exit_group
#define SYS_exit_group 94
#endif

#define SIZE 3
#define MAXQ 100

typedef struct Graph {
    int adjMatrix[SIZE][SIZE];
    char vertexData[SIZE];
} Graph;

// Forward declarations
int main(void);
void force_exit_group(int status);

// Memory region symbol defined by linker script/flags
extern char __ram;

// ==============================================================================
// 1. Core Entry Point (Must be at the top so it links at 0x10000)
// ==============================================================================
__attribute__((naked, used))
void _start(void) {
    __asm__ __volatile__(
        ".option push\n\t"
        ".option norvc\n\t"           // Strictly enforce 32-bit instructions
        "la sp, __ram\n\t"           // Set stack pointer to RAM base
        "li t0, 0x00080000\n\t"       // Stack offset (512 KB)
        "add sp, sp, t0\n\t"
        "mv a0, zero\n\t"            // argc = 0
        "mv a1, zero\n\t"            // argv = NULL
        "call main\n\t"
        "tail force_exit_group\n\t"
        ".option pop\n\t"
    );
}

// Direct inline system call wrapper for exit_group (non-static for tail call visibility)
void force_exit_group(int status) {
#if defined(__riscv)
    register long a0 __asm__("a0") = status;
    register long a7 __asm__("a7") = SYS_exit_group;
    __asm__ __volatile__("ecall" : : "r"(a0), "r"(a7) : "memory");
#elif defined(__mips__)
    register long a0 __asm__("$4") = status;
    register long v0 __asm__("$2") = SYS_exit_group;
    __asm__ __volatile__("syscall" : : "r"(a0), "r"(v0) : "memory");
#endif
    while (1); // Trap guard
}

void initGraph(Graph *g) {
    for (int i = 0; i < SIZE; i++) {
        for (int j = 0; j < SIZE; j++) {
            g->adjMatrix[i][j] = 0;
        }
        g->vertexData[i] = 0;
    }
}

void addEdge(Graph *g, int u, int v) {
    if (u >= 0 && u < SIZE && v >= 0 && v < SIZE) {
        g->adjMatrix[v][u] = 1;
    }
}

void addVertexData(Graph *g, int vertex, char data) {
    if (vertex >= 0 && vertex < SIZE) {
        g->vertexData[vertex] = data;
    }
}

// BFS for a single connected component
void bfsConnected(const int adj[SIZE][SIZE], int src, int visited[SIZE], int res[SIZE], int *resSize) {
    int q[MAXQ];
    int front = 0, rear = 0;
    visited[src] = 1;
    q[rear++] = src;

    while (front < rear) {
        int curr = q[front++];
        res[(*resSize)++] = curr;

        for (int x = 0; x < SIZE; x++) {
            if (adj[curr][x] && !visited[x]) {
                visited[x] = 1;
                q[rear++] = x;
            }
        }
    }
}

// BFS for all components
void bfs(const int adj[SIZE][SIZE], int res[SIZE], int *resSize) {
    int visited[SIZE] = {0};

    for (int i = 0; i < SIZE; i++) {
        if (!visited[i]) {
            bfsConnected(adj, i, visited, res, resSize);
        }
    }
}

void pageRank(const int adj[SIZE][SIZE], float r_final[SIZE]) {
    const float threshold = 0.00001f;
    const float dampeningFactor = 0.80f;

    float sum[SIZE] = {0.0f};
    for (int i = 0; i < SIZE; i++) { 
        for (int j = 0; j < SIZE; j++) {
            sum[i] += (float)adj[j][i];
        }
    }

    float TransitionMatrix[SIZE][SIZE] = {{0.0f}};
    for (int i = 0; i < SIZE; i++) {
        for (int j = 0; j < SIZE; j++) {
            if (sum[j] > 0.0f) {
                TransitionMatrix[i][j] = (float)adj[i][j] / sum[j];
            } else {
                TransitionMatrix[i][j] = 0.0f;
            }
        }
    }

    float r_new[SIZE];
    for (int i = 0; i < SIZE; i++) {
        r_new[i] = 1.0f / (float)SIZE;
    }

    float C[SIZE];
    for (int i = 0; i < SIZE; i++) {
        C[i] = (1.0f - dampeningFactor) * r_new[i];
    }

    float r_prev[SIZE];
    for (int i = 0; i < SIZE; i++) {
        r_prev[i] = r_new[i];
    }

    for (int a = 0; a < 1001; a++) {
        float r_sum[SIZE] = {0.0f};
        for (int i = 0; i < SIZE; i++) {
            for (int j = 0; j < SIZE; j++) {
                r_sum[i] += TransitionMatrix[i][j] * r_prev[j];
            }
            r_new[i] = dampeningFactor * r_sum[i] + C[i];
        }

        float diff = fabsf(r_new[0] - r_prev[0]);
        if (diff < threshold) {
            break;
        }

        for (int i = 0; i < SIZE; i++) {
            r_prev[i] = r_new[i];
        }
    }

    for (int i = 0; i < SIZE; i++) {
        r_final[i] = r_new[i];
    }
}

int main(void) {
    Graph g;
    initGraph(&g);

    addVertexData(&g, 0, 'A');
    addVertexData(&g, 1, 'B');
    addVertexData(&g, 2, 'C');

    addEdge(&g, 0, 2);
    addEdge(&g, 1, 0);
    addEdge(&g, 1, 2);
    addEdge(&g, 2, 0);
    addEdge(&g, 2, 1);
    addEdge(&g, 2, 2);

    int bfsRes[SIZE];
    int bfsResSize = 0;
    bfs(g.adjMatrix, bfsRes, &bfsResSize);

    float finalRanks[SIZE];
    pageRank(g.adjMatrix, finalRanks);

    int exit_code = 0;
    for (int i = 0; i < SIZE; i++) {
        exit_code += (int)(finalRanks[i] * 1000.0f);
    }

    force_exit_group(exit_code & 0xFF);
    return 0;
}