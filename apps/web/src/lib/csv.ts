/** Экспорт таблицы страницы в CSV на стороне клиента (UTF-8 с BOM, чтобы Excel прочитал кириллицу). */
function cell(value: unknown): string {
  const text = value === null || value === undefined ? '' : typeof value === 'object' ? JSON.stringify(value) : String(value)
  return /[";\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export function toCsv(rows: Record<string, unknown>[], columns?: string[]): string {
  const keys = columns ?? [...new Set(rows.flatMap((r) => Object.keys(r)))]
  return [keys.join(';'), ...rows.map((r) => keys.map((k) => cell(r[k])).join(';'))].join('\r\n')
}

export function downloadCsv(filename: string, rows: Record<string, unknown>[], columns?: string[]): void {
  const blob = new Blob([`﻿${toCsv(rows, columns)}`], { type: 'text/csv;charset=utf-8' })
  const link = document.createElement('a')
  link.href = URL.createObjectURL(blob)
  link.download = filename
  link.click()
  URL.revokeObjectURL(link.href)
}
