.pragma library

function first(rows) {
  if (!Array.isArray(rows)) return ""
  for (var row = 0; row < rows.length; row++) {
    if (Array.isArray(rows[row]) && rows[row].length > 0)
      return String(rows[row][0])
  }
  return ""
}

function position(rows, target) {
  if (!Array.isArray(rows)) return null
  for (var row = 0; row < rows.length; row++) {
    if (!Array.isArray(rows[row])) continue
    for (var column = 0; column < rows[row].length; column++) {
      if (String(rows[row][column]) === String(target))
        return { row: row, column: column }
    }
  }
  return null
}

function contains(rows, target) {
  return position(rows, target) !== null
}

function move(rows, target, dx, dy) {
  var current = position(rows, target)
  if (!current) return first(rows)

  var row = current.row
  var column = current.column
  if (Number(dy) !== 0) {
    row = Math.max(0, Math.min(rows.length - 1, row + (Number(dy) > 0 ? 1 : -1)))
    column = Math.min(column, rows[row].length - 1)
  } else if (Number(dx) !== 0) {
    column = Math.max(0, Math.min(rows[row].length - 1,
      column + (Number(dx) > 0 ? 1 : -1)))
  }
  return String(rows[row][column])
}
