/** The Files tab's list: versions grouped per artifact, newest first, one search box + type chips. */
import { CATEGORIES, type Category, fileCategory } from './preview.ts'
import { fileSize } from '../format.ts'
import type { ChatFile } from '../types.ts'

/** All saved versions of one file (or one file with no versions), newest first. */
export interface FileGroup {
  id: string
  items: ChatFile[]
}

export interface FileFilter {
  query?: string
  category?: string
}

const newestCreatedAt = (group: FileGroup): string => group.items[0]?.createdAt ?? ''

function newestVersionFirst(a: ChatFile, b: ChatFile): number {
  return (b.version || 0) - (a.version || 0) || b.createdAt.localeCompare(a.createdAt)
}

/** One group per artifact (or per file without one); `items` hold its versions, newest first. */
export function groupVersions(files: readonly ChatFile[] = []): FileGroup[] {
  const groups = new Map<string, ChatFile[]>()
  for (const file of files) {
    const key = file.artifactId || file.id
    groups.set(key, [...(groups.get(key) || []), file])
  }
  return [...groups.entries()]
    .map(([id, items]) => ({ id, items: [...items].sort(newestVersionFirst) }))
    .sort((a, b) => newestCreatedAt(b).localeCompare(newestCreatedAt(a)))
}

function fileMatches(file: ChatFile, needle: string, category: string): boolean {
  const named = !needle || file.name.toLowerCase().includes(needle)
  return named && (!category || fileCategory(file) === category)
}

/** Groups with any version matching the search text and type chip (all versions stay listed). */
export function filterGroups(groups: readonly FileGroup[], { query = '', category = '' }: FileFilter = {}): FileGroup[] {
  const needle = query.trim().toLowerCase()
  return groups.filter(group => group.items.some(file => fileMatches(file, needle, category)))
}

/** The type chips worth showing: only types the person actually has, in a fixed order. */
export function presentCategories(files: readonly ChatFile[] = []): Category[] {
  const present = new Set(files.map(fileCategory))
  return CATEGORIES.filter(category => present.has(category.id))
}

/** The version a group shows: the one picked in Details, else the newest. */
export function shownVersion(group: FileGroup, pickedId: string): ChatFile | undefined {
  return group.items.find(item => item.id === pickedId) || group.items[0]
}

/** The ready PDF the server rendered from this file (e.g. a document), if there is one. */
export function renderedPdfOf(file: ChatFile, files: readonly ChatFile[] = []): ChatFile | null {
  return files.find(item => item.id === file.previewFileId && item.state === 'ready' && item.mediaType === 'application/pdf') || null
}

const SHORT_DATE = Object.freeze({ month: 'short', day: 'numeric' })

/** "1.7 MiB · Oct 1 · 3 versions", or what is still missing for an unfinished upload. */
export function fileMeta(file: ChatFile, versionCount = 1): string {
  const parts = [fileSize(file.size), new Date(file.createdAt).toLocaleDateString([], SHORT_DATE)]
  if (versionCount > 1) parts.push(`${versionCount} versions`)
  if (file.state !== 'ready') parts.push(`${fileSize(file.received || 0)} received, not ready yet`)
  return parts.join(' · ')
}
