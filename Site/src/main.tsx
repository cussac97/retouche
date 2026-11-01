import { StrictMode, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { RetoucheHero } from './hero/RetoucheHero'
import './page.css'

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
          <button type="button" className="hero__replay" onClick={replay}>
            Rejouer la démo
          </button>
        </div>
        <div className="hero__demo" data-hidden={hidden || undefined}>
          <RetoucheHero key={run} />
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
