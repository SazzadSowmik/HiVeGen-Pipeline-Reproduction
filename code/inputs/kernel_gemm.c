void gemm(int M, int N, int K,
          const float *A, const float *B, float *C) {
  for (int i = 0; i < M; ++i)
    for (int j = 0; j < N; ++j) {
      float acc = 0.0f;
      for (int k = 0; k < K; ++k)
        acc += A[i*K + k] * B[k*N + j];
      C[i*N + j] = acc;
    }
}
