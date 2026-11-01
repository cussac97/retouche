import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { Download, Github, RotateCcw } from 'lucide-react'
import { RetoucheHero } from './hero/RetoucheHero'
import './page.css'

const REPO = 'https://github.com/cussac97/retouche'
// Every release ships the same file name, so this always serves the latest one
const DOWNLOAD = `${REPO}/releases/latest/download/Retouche.dmg`

function Page() {
  // Replay remounts the demo at its story boundary; the click explains the fresh
  // start, and the scene fades out and back in so the email never vanishes in one frame.
  const [run, setRun] = useState(0)
  const [hidden, setHidden] = useState(false)
  const replay = () => {
    setHidden(true)
    setTimeout(() => {
      setRun((n) => n + 1)
      setHidden(false)
    }, 220)
  }
  return (
    <main className="page">
      <section className="hero">
        <div className="hero__copy">
          <img className="hero__icon" src="/icon.png" width={72} height={72} alt="" />
          <h1>Retouche</h1>
          <p className="hero__lede">La correction automatique de l'iPhone, dans toutes les apps du Mac.</p>
          <p>
            Retouche corrige vos fautes de frappe au moment où vous tapez espace, en français comme en anglais, phrase par phrase. Quand deux
            corrections se valent, Apple Intelligence choisit d'après le sens de la phrase. Rien ne quitte votre Mac.
          </p>
          <div className="hero__actions">
            <a className="hero__button hero__button--primary" href={DOWNLOAD}>
              <Download size={16} strokeWidth={2} aria-hidden />
              Télécharger pour Mac
            </a>
            <a className="hero__button" href={REPO}>
              <Github size={16} strokeWidth={2} aria-hidden />
              Code source
            </a>
          </div>
          <p className="hero__meta">
            Gratuit et open source · macOS 14 ou plus récent ·{' '}
            <a href={`${REPO}#installer`}>Première ouverture</a>
          </p>
        </div>
        <div className="hero__demo">
          <div className="hero__stage" data-hidden={hidden || undefined}>
            <RetoucheHero key={run} />
          </div>
          <button type="button" className="hero__replay" onClick={replay}>
            <RotateCcw size={14} strokeWidth={2} aria-hidden />
            Rejouer la démo
          </button>
        </div>
      </section>
    </main>
  )
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Page />
  </StrictMode>,
)
