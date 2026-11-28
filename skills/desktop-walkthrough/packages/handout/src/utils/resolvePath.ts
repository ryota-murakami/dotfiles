/**
 * Resolve a relative path against a folder, folding `.` and `..`, the way a file system would.
 *
 * @param folder - An absolute folder path.
 * @param relative - A path relative to it (`shot.png`, `./img/a.png`, `../assets/b.png`).
 * @returns The absolute path; never above `/`.
 *
 * @example
 * resolvePath('/r/pages', './img/a.png')     // '/r/pages/img/a.png'
 * resolvePath('/r/pages', '../assets/b.png') // '/r/assets/b.png'
 */
export function resolvePath(folder: string, relative: string): string {
  const parts: string[] = []
  for (const part of `${folder}/${relative}`.split('/')) {
    if (part === '' || part === '.') continue
    if (part === '..') parts.pop()
    else parts.push(part)
  }
  return `/${parts.join('/')}`
}
