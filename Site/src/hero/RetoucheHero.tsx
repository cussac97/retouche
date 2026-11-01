import { useEffect, useMemo, useState } from 'react'
import { Paperclip, Send } from 'lucide-react'
import { Connector, Stage, Window, type Act, type Layout, type Rect } from '../kit'
import { morph, spring } from './morph'
import './retouche.css'

// Retouche's hero: an email typed in Mail, seen close up. Each slip is fixed as
// its space is typed, with the word's own letters: "deja" at once, "cafr" half a
// second later once Apple Intelligence has read the sentence (café, not car),
// and "teh" in the English line that follows.

type Fly = { id: number; from: string; to: string; at: string }
type S = {
  l1: string
  l2: string
  focus: 'l1' | 'l2'
  typing: boolean
  flies: Fly[]
  next: number
  note: boolean
}

const LINE1 = 'Je suis déjà au café de la gare.'
const LINE2 = 'No rush, the coffee is on me.'

const initial: S = { l1: '', l2: '', focus: 'l1', typing: false, flies: [], next: 0, note: false }
const poster: S = { ...initial, l1: LINE1, l2: LINE2, focus: 'l2', note: true }

// The window is drawn at its real size and scaled as a whole, chrome and all.
const ZOOM: Record<Layout, { x: number; y: number; scale: number }> = {
  wide: { x: 40, y: 40, scale: 1.4 },
  compact: { x: 16, y: 16, scale: 1.2 },
}

// The body's type, shared by the text and the letters that float above it.
const FONT_SIZE = 17
const LINE_HEIGHT = 22
const FAMILY = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif'

async function type(a: Act<S>, key: 'l1' | 'l2', text: string) {
  await a.set({ typing: true })
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    await a.set((s) => ({ [key]: s[key] + ch }))
    // Uneven but repeatable: quicker inside a word, a beat longer after a space
    const jitter = 0.75 + 0.5 * Math.abs(Math.sin((i + 1) * 12.9898))
    await a.wait((ch === ' ' ? 90 : 58) * jitter)
  }
  await a.set({ typing: false })
}

/** Replaces one word, as Retouche's backspaces do, and lifts its letters above the line. */
async function fix(a: Act<S>, key: 'l1' | 'l2', index: number, to: string, note?: boolean) {
  await a.set((s) => {
    const words = s[key].split(' ')
    const fly = { id: s.next, from: words[index], to, at: `${key}-${index}` }
    words[index] = to
    return { [key]: words.join(' '), flies: [...s.flies.slice(-2), fly], next: s.next + 1, ...(note && { note: true }) }
  })
}

async function script(a: Act<S>) {
  await a.wait(900)

  // An accent, fixed on the space
  await type(a, 'l1', 'Je suis deja ')
  a.mark('deja')
  await fix(a, 'l1', 2, 'déjà')

  // car or café? Apple Intelligence answers while the next words are typed,
  // and the note says why as the letters lift
  await type(a, 'l1', 'au cafr ')
  a.mark('cafr')
  const late = (async () => {
    await a.wait(620)
    a.mark('cafe')
    await fix(a, 'l1', 4, 'café', true)
  })()
  await type(a, 'l1', 'de la gare.')
  await late
  await a.wait(1600)

  // A new line, in English: two letters swapped
  await a.set({ focus: 'l2' })
  await a.wait(450)
  await type(a, 'l2', 'No rush, teh ')
  a.mark('teh')
  await fix(a, 'l2', 2, 'the')
  await type(a, 'l2', 'coffee is on me.')
  await a.wait(400)
  a.mark('done')
}

export function RetoucheHero() {
  return (
    <Stage
      width={600}
      height={380}
      compact={{ below: 520, width: 374, height: 320 }}
      fill
      initial={initial}
      poster={poster}
      script={script}
      play="once"
      greys="cool"
      accent="#4a7aff"
      className="rt"
    >
      {(s, rect, layout) => {
        const zoom = ZOOM[layout]
        // Stage px to the zoomed window's own px, for what floats over its text
        const local = (r: Rect): Rect => ({ x: (r.x - zoom.x) / zoom.scale, y: (r.y - zoom.y) / zoom.scale, width: r.width / zoom.scale, height: r.height / zoom.scale })
        return (
          <>
            <div className="rt-zoom" style={{ left: zoom.x, top: zoom.y, scale: String(zoom.scale) }}>
              <Window title="Samedi" toolbar={<span />} lead={<Tools />} className="rt-win">
                <div className="rt-field">
                  <span className="rt-field__label">À :</span>
                  <span className="rt-token">Léa Moreau</span>
                </div>
                <div className="rt-field">
                  <span className="rt-field__label">Objet :</span>
                  <span>Samedi</span>
                </div>
                <div className="rt-body" style={{ font: `${FONT_SIZE}px/${LINE_HEIGHT}px ${FAMILY}` }}>
                  <div className="rt-line">Salut Léa,</div>
                  <div className="rt-line" />
                  <Line name="l1" text={s.l1} caret={s.focus === 'l1'} typing={s.typing} />
                  <Line name="l2" text={s.l2} caret={s.focus === 'l2'} typing={s.typing} />
                </div>
              </Window>

              {s.flies.map((f) => (
                <Morph key={f.id} from={f.from} to={f.to} at={local(rect(f.at))} />
              ))}
            </div>

            <Note show={s.note} word={rect('l1-4')} layout={layout} />
          </>
        )
      }}
    </Stage>
  )
}

function Tools() {
  return (
    <span className="rt-tools">
      <Send size={16} strokeWidth={1.75} aria-hidden />
      <Paperclip size={16} strokeWidth={1.75} aria-hidden />
    </span>
  )
}

/** A typed line, one span per word so each can be measured. */
function Line({ name, text, caret, typing }: { name: string; text: string; caret: boolean; typing: boolean }) {
  const words = text.split(' ')
  return (
    <div className="rt-line">
      {words.map((word, i) => (
        <span key={i}>
          {i > 0 && ' '}
          <span data-target={`${name}-${i}`}>{word}</span>
        </span>
      ))}
      {caret && <span className="rt-caret" data-blink={!typing || undefined} />}
    </div>
  )
}

// The overlay's three phases, as Retouche/Overlay/OverlayController.swift runs them (ms)
const REARRANGE_AT = 150
const LAND_AT = 710
const LAND_FOR = 200
const DONE_AT = LAND_AT + LAND_FOR + 40

let canvas: HTMLCanvasElement | null = null
function measure(text: string) {
  canvas ??= document.createElement('canvas')
  const ctx = canvas.getContext('2d')!
  ctx.font = `${FONT_SIZE}px ${FAMILY}`
  return ctx.measureText(text).width
}

/** film.mjs --slow slows the stage down; the letters keep its pace. */
function slowdown() {
  return (window as unknown as { __stageshow?: { slow?: number } }).__stageshow?.slow ?? 1
}

/** The typed word, lifted just above the line, rearranging into the correction before it lands on it. */
function Morph({ from, to, at }: { from: string; to: string; at: Rect }) {
  const plan = useMemo(() => morph(from, to, measure), [from, to])
  const [t, setT] = useState(0)

  useEffect(() => {
    const start = performance.now()
    const slow = slowdown()
    let raf = requestAnimationFrame(function tick() {
      const elapsed = (performance.now() - start) / slow
      setT(elapsed)
      if (elapsed < DONE_AT) raf = requestAnimationFrame(tick)
    })
    return () => cancelAnimationFrame(raf)
  }, [])

  const lift = spring(t / 1000, 0.24, 0.3)
  const progress = spring((t - REARRANGE_AT) / 1000, 0.5, 0.28)
  // SwiftUI's easeIn, closely enough
  const land = Math.pow(Math.min(Math.max((t - LAND_AT) / LAND_FOR, 0), 1), 1.7)
  const height = lift - land
  const rise = LINE_HEIGHT * 1.1
  const em = FONT_SIZE

  return (
    <div
      className="rt-morph"
      aria-hidden
      style={{
        left: at.x,
        top: at.y,
        height: at.height,
        font: `${FONT_SIZE}px ${FAMILY}`,
        opacity: Math.min(lift, 1) * (1 - land),
        transform: `translateY(${-rise * height}px) scale(${1 + 0.06 * height})`,
      }}
    >
      {plan.letters.map((letter) => {
        // Springs overshoot past 1: horizontal travel keeps it, the rest settles
        const travel = Math.max(0, (progress - letter.delay) / (1 - letter.delay))
        const k = Math.min(travel, 1)
        const arc = Math.sin(Math.PI * k)
        const direction = letter.to >= letter.from ? 1 : -1
        let x = letter.from + (letter.to - letter.from) * travel
        let y = 0
        let opacity = 1
        let blur = 0
        let scale = 1
        let angle = 0
        switch (letter.motion) {
          case 'slide': {
            // A ripple runs through the word from left to right
            const start = 0.4 * (letter.to / Math.max(plan.width, 1))
            y = -Math.sin(Math.PI * Math.min(Math.max((progress - start) / 0.5, 0), 1)) * em * 0.22
            break
          }
          case 'hop':
            y = -arc * em * 0.9
            scale = 1 + 0.3 * arc
            angle = arc * 14 * direction
            break
          case 'enter':
            y = -(1 - k) * em * 1.2
            opacity = k
            blur = (1 - k) * 3
            scale = 0.5 + 0.5 * k
            break
          case 'leave':
            x = letter.from
            y = k * em * 0.9
            opacity = Math.max(0, 1 - k * 1.6)
            blur = k * 3
            scale = 1 - 0.45 * k
            angle = k * 18
            break
        }
        return (
          <span
            key={letter.id}
            className="rt-letter"
            data-leave={letter.motion === 'leave' || undefined}
            style={{
              opacity,
              filter: blur > 0.05 ? `blur(${blur}px)` : undefined,
              transform: `translate(${x}px, ${y}px) rotate(${angle}deg) scale(${scale})`,
            }}
          >
            {letter.ch}
          </span>
        )
      })}
    </div>
  )
}

/** One short note in the empty line above, to the right of "café", tied to it by a leader. */
function Note({ show, word, layout }: { show: boolean; word: Rect; layout: Layout }) {
  const x = word.x + word.width / 2
  const y = word.y - (ZOOM[layout].scale * LINE_HEIGHT) / 2 - 3
  const reach = layout === 'wide' ? 30 : 22
  return (
    <>
      <Connector show={show} from={{ x: x + reach, y }} to={{ x, y: word.y - 3 }} route="h" radius={6} className="rt-leader" />
      <div className="rt-note" data-show={show || undefined} style={{ left: x + reach, top: y }}>
        {layout === 'wide' && 'Le sens de la phrase : '}
        <b>café</b>, pas car
      </div>
    </>
  )
}
