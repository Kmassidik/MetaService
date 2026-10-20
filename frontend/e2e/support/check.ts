// The pass/fail list every browser test prints, and the exit code that follows from it.
const results: boolean[] = []

/** Records one check and prints its line; a failed one also prints the detail. */
export function check(name: string, ok: boolean, detail = ''): void {
  results.push(ok)
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !detail ? '' : ': ' + detail}`)
}

/** Prints the totals and ends the program with 0 when every check passed, 1 otherwise. */
export function finish(): never {
  const failed = results.filter((ok) => !ok).length
  console.log(`\n${results.length - failed} passed, ${failed} failed`)
  process.exit(failed ? 1 : 0)
}
