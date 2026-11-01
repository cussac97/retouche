// Port of Retouche/Overlay/LetterMorph.swift: how each letter travels when the
// typed word becomes its correction. Letters common to both words, in order,
// slide to their new place; a letter that changed place (a transposition) hops
// over the others; missing letters drop in, extra ones fall away.

export type Motion = 'slide' | 'hop' | 'enter' | 'leave'

export type Letter = {
  id: number
  ch: string
  motion: Motion
  /** Horizontal positions in the typed word and in the correction. */
  from: number
  to: number
  /** Share of the animation to wait before moving, for staggered entries. */
  delay: number
}

export function morph(original: string, replacement: string, measure: (text: string) => number) {
  const typed = [...original]
  const corrected = [...replacement]
  const typedX = offsets(typed, measure)
  const correctedX = offsets(corrected, measure)

  const slides = commonSubsequence(typed, corrected)
  const used = new Set(slides.values())
  let targets = corrected.map((_, i) => i).filter((i) => !used.has(i))
  const hops = new Map<number, number>()
  typed.forEach((ch, index) => {
    if (slides.has(index)) return
    const candidates = targets.filter((t) => corrected[t] === ch)
    if (!candidates.length) return
    const target = candidates.reduce((best, t) => (Math.abs(t - index) < Math.abs(best - index) ? t : best))
    hops.set(index, target)
    targets = targets.filter((t) => t !== target)
  })

  const letters: Letter[] = []
  typed.forEach((ch, index) => {
    const from = typedX[index]
    const slide = slides.get(index)
    const hop = hops.get(index)
    if (slide !== undefined) letters.push({ id: letters.length, ch, motion: 'slide', from, to: correctedX[slide], delay: 0 })
    else if (hop !== undefined) letters.push({ id: letters.length, ch, motion: 'hop', from, to: correctedX[hop], delay: 0 })
    else letters.push({ id: letters.length, ch, motion: 'leave', from, to: from, delay: 0 })
  })
  targets
    .sort((x, y) => x - y)
    .forEach((index, rank) => {
      const x = correctedX[index]
      letters.push({ id: letters.length, ch: corrected[index], motion: 'enter', from: x, to: x, delay: Math.min(rank * 0.08, 0.3) })
    })
  return { letters, width: Math.max(typedX[typed.length], correctedX[corrected.length]) }
}

/** Left edge of each character, followed by the total width. */
function offsets(chars: string[], measure: (text: string) => number) {
  let x = 0
  const result = [x]
  for (const ch of chars) {
    x += measure(ch)
    result.push(x)
  }
  return result
}

/** Longest common subsequence, as typed index → corrected index. */
function commonSubsequence(a: string[], b: string[]) {
  const lengths = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0))
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      lengths[i][j] = a[i] === b[j] ? lengths[i + 1][j + 1] + 1 : Math.max(lengths[i + 1][j], lengths[i][j + 1])
    }
  }
  const pairs = new Map<number, number>()
  let i = 0
  let j = 0
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      pairs.set(i, j)
      i++
      j++
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) i++
    else j++
  }
  return pairs
}

/** SwiftUI's `.spring(duration:bounce:)`, settling from 0 to 1. */
export function spring(t: number, duration: number, bounce: number) {
  if (t <= 0) return 0
  const omega = (2 * Math.PI) / duration
  const zeta = 1 - bounce
  const damped = omega * Math.sqrt(1 - zeta * zeta)
  return 1 - Math.exp(-zeta * omega * t) * (Math.cos(damped * t) + ((zeta * omega) / damped) * Math.sin(damped * t))
}
