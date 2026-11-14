declare module 'named-placeholders' {
  const createCompiler: (config?: {
    placeholder?: string;
    cache?: number | false;
  }) => (query: string, params: Record<string, unknown>) => [string, unknown[]];
  export default createCompiler;
}
