#include <stdint.h>

#ifndef NULL
#define NULL ((void*)0)
#endif

#ifndef SYS_exit
#define SYS_exit 93
#endif

#ifndef SYS_getpid
#define SYS_getpid 172
#endif

#define SIZE 3
#define MAXQ 100

typedef struct Graph {
    int adjMatrix[SIZE][SIZE];
    char vertexData[SIZE];
} Graph;

void force_exit(void);

static float custom_fabsf(float x) {
    return (x < 0.0f) ? -x : x;
}

void force_exit(void) {
    __asm__ __volatile__(
        "li a7, 93\n"
        "ecall\n"
        "fence\n"           // Memory fence to prevent reordering
        "1: j 1b\n"         // Infinite loop (can't fetch past this)
        : 
        : 
        : "memory"
    );
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

void bfs(const int adj[SIZE][SIZE], int res[SIZE], int *resSize) {
    int visited[SIZE] = {0};
    for (int i = 0; i < SIZE; i++) {
        if (!visited[i]) {
            bfsConnected(adj, i, visited, res, resSize);
        }
    }
}

void pageRank(const int adj[SIZE][SIZE], float r_final[SIZE]) {
    const float threshold = 0.1f;
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

    for (int a = 0; a < 5; a++) {
        float r_sum[SIZE] = {0.0f};
        for (int i = 0; i < SIZE; i++) {
            for (int j = 0; j < SIZE; j++) {
                r_sum[i] += TransitionMatrix[i][j] * r_prev[j];
            }
            r_new[i] = dampeningFactor * r_sum[i] + C[i];
        }

        float diff = custom_fabsf(r_new[0] - r_prev[0]);
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

int main(int argc, char **argv) {
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

    // Get unique process ID to stagger exits
    register long a7 __asm__("a7") = SYS_getpid;
    register long my_pid __asm__("a0");
    __asm__ __volatile__("ecall" : "=r"(my_pid) : "r"(a7) : "memory");

    // Multiply the PID's last digit by a delay to ensure cores exit one at a time
    int stagger_multiplier = my_pid % 10;
    volatile int delay = 0;
    for (int i = 0; i < stagger_multiplier * 40000; i++) {
        delay++;
    }

    register long exit_code __asm__("a0") = 0;
    force_exit();
}

void _start(void) {
    __asm__ __volatile__(
        ".option push\n\t"
        ".option norvc\n\t"           
        
        "ld a0, 0(sp)\n\t"       
        "addi a1, sp, 8\n\t"     
        "andi sp, sp, -16\n\t"   
        
        "call main\n\t"          
        "mv a0, a0\n\t"          
        "tail force_exit\n\t"    
        
        ".option pop\n\t"
    );
}

