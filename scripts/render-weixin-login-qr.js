#!/usr/bin/env node

const fs = require('fs');
const { execFileSync } = require('child_process');

function usage() {
  console.error('Usage: node scripts/render-weixin-login-qr.js --input <login.log> --pbm <out.pbm> [--png <out.png>] [--scale <pixels>] [--margin <modules>]');
  process.exit(1);
}

function parseArgs(argv) {
  const options = {
    scale: 12,
    margin: 4,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];

    if (arg === '--input' && next) {
      options.input = next;
      index += 1;
    } else if (arg === '--pbm' && next) {
      options.pbm = next;
      index += 1;
    } else if (arg === '--png' && next) {
      options.png = next;
      index += 1;
    } else if (arg === '--scale' && next) {
      options.scale = Number(next);
      index += 1;
    } else if (arg === '--margin' && next) {
      options.margin = Number(next);
      index += 1;
    } else {
      usage();
    }
  }

  if (!options.input || !options.pbm) {
    usage();
  }

  if (!Number.isInteger(options.scale) || options.scale <= 0) {
    throw new Error('scale must be a positive integer');
  }

  if (!Number.isInteger(options.margin) || options.margin < 0) {
    throw new Error('margin must be a non-negative integer');
  }

  return options;
}

function extractQrBlock(text) {
  const groups = [];
  let current = [];

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/\s+$/u, '');
    if (/[█▀▄]/u.test(line)) {
      current.push(line);
      continue;
    }

    if (current.length > 0) {
      groups.push(current);
      current = [];
    }
  }

  if (current.length > 0) {
    groups.push(current);
  }

  if (groups.length === 0) {
    throw new Error('no terminal QR block found in login log');
  }

  return groups[groups.length - 1];
}

function blockToMatrix(blockLines) {
  const width = Math.max(...blockLines.map((line) => Array.from(line).length));
  const rows = [];

  for (const line of blockLines) {
    const chars = Array.from(line.padEnd(width, ' '));
    const top = [];
    const bottom = [];

    for (const char of chars) {
      if (char === '█') {
        top.push(1);
        bottom.push(1);
      } else if (char === '▀') {
        top.push(1);
        bottom.push(0);
      } else if (char === '▄') {
        top.push(0);
        bottom.push(1);
      } else {
        top.push(0);
        bottom.push(0);
      }
    }

    rows.push(top, bottom);
  }

  return rows;
}

function trimWhitespace(matrix) {
  let top = 0;
  let bottom = matrix.length - 1;
  let left = 0;
  let right = matrix[0].length - 1;

  const isWhiteRow = (row) => row.every((value) => value === 0);
  const isWhiteCol = (column) => matrix.every((row) => row[column] === 0);

  while (top <= bottom && isWhiteRow(matrix[top])) top += 1;
  while (bottom >= top && isWhiteRow(matrix[bottom])) bottom -= 1;
  while (left <= right && isWhiteCol(left)) left += 1;
  while (right >= left && isWhiteCol(right)) right -= 1;

  if (top > bottom || left > right) {
    throw new Error('terminal QR block is empty after trimming');
  }

  const trimmed = [];
  for (let rowIndex = top; rowIndex <= bottom; rowIndex += 1) {
    trimmed.push(matrix[rowIndex].slice(left, right + 1));
  }

  return trimmed;
}

function addQuietZone(matrix, margin) {
  const qrSize = matrix.length;
  const paddedSize = qrSize + margin * 2;
  const padded = Array.from({ length: paddedSize }, () => Array(paddedSize).fill(0));

  for (let row = 0; row < qrSize; row += 1) {
    for (let column = 0; column < qrSize; column += 1) {
      padded[row + margin][column + margin] = matrix[row][column];
    }
  }

  return padded;
}

function scaleMatrix(matrix, scale) {
  const pixels = [];

  for (const row of matrix) {
    const expanded = [];
    for (const cell of row) {
      for (let column = 0; column < scale; column += 1) {
        expanded.push(cell);
      }
    }
    for (let repeat = 0; repeat < scale; repeat += 1) {
      pixels.push(expanded.slice());
    }
  }

  return pixels;
}

function writePbm(filePath, pixels) {
  const width = pixels[0].length;
  const height = pixels.length;
  const body = pixels.map((row) => row.join(' ')).join('\n');
  fs.writeFileSync(filePath, `P1\n${width} ${height}\n${body}\n`);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const text = fs.readFileSync(options.input, 'utf8');
  const block = extractQrBlock(text);
  const rawMatrix = blockToMatrix(block);
  const trimmedMatrix = trimWhitespace(rawMatrix);

  if (trimmedMatrix.length !== trimmedMatrix[0].length) {
    throw new Error(`unexpected QR aspect ratio ${trimmedMatrix[0].length}x${trimmedMatrix.length}`);
  }

  const qrMatrix = addQuietZone(trimmedMatrix, options.margin);
  const pixels = scaleMatrix(qrMatrix, options.scale);

  fs.mkdirSync(require('path').dirname(options.pbm), { recursive: true });
  writePbm(options.pbm, pixels);

  if (options.png) {
    execFileSync(process.env.CONVERT_BIN || 'convert', [options.pbm, options.png], { stdio: 'pipe' });
  }

  process.stdout.write(JSON.stringify({
    modules: trimmedMatrix.length,
    imageSize: pixels.length,
    pbm: options.pbm,
    png: options.png || null,
  }));
}

main();
