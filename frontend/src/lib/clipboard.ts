// Copying text for a button. Answers whether it worked: the browser refuses without permission or on a page that is not secure.
export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}
