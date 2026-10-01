/** Экспорт таблицы страницы в CSV на стороне клиента (UTF-8 с BOM, чтобы Excel прочитал кириллицу). */
/** Числа — с запятой и без разделителя тысяч: так их понимает Excel с русскими настройками (разделитель полей — «;»). */
function cell(value: unknown): string {
  const text = value === null || value === undefined ? ''
    : typeof value === 'number' ? (Number.isFinite(value) ? value.toLocaleString('ru-RU', { useGrouping: false, maximumFractionDigits: 2 }) : '')
    : typeof value === 'object' ? JSON.stringify(value) : String(value)
  return /[";\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export function toCsv(rows: Record<string, unknown>[], columns?: string[]): string {
  const keys = columns ?? [...new Set(rows.flatMap((r) => Object.keys(r)))]
  return [keys.join(';'), ...rows.map((r) => keys.map((k) => cell(r[k])).join(';'))].join('\r\n')
}

export function downloadCsv(filename: string, rows: Record<string, unknown>[], columns?: string[]): void {
  const blob = new Blob(['\uFEFF', toCsv(rows, columns)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.style.display = 'none'
  // ссылка в документе и отложенный revoke: иначе часть браузеров отменяет скачивание до его начала
  document.body.appendChild(link)
  link.click()
  setTimeout(() => {
    link.remove()
    URL.revokeObjectURL(url)
  }, 1000)
}
