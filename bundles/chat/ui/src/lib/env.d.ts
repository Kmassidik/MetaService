// Files Vite turns into URLs: the import is the public path of the file.
declare module '*.webp' {
  const url: string
  export default url
}

declare module '*.svg' {
  const url: string
  export default url
}

declare module 'pdfjs-dist/build/pdf.worker.min.mjs?url' {
  const url: string
  export default url
}
