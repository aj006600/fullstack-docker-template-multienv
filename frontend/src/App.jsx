import { useEffect, useState } from 'react'

export default function App() {
  const [message, setMessage] = useState('loading...')

  useEffect(() => {
    fetch('/api/message')
      .then((res) => res.json())
      .then((data) => setMessage(data.message))
      .catch(() => setMessage('failed to reach backend'))
  }, [])

  return (
    <main style={{ fontFamily: 'sans-serif', padding: '2rem' }}>
      <h1>Fullstack Minimal</h1>
      <p>
        Backend says: <strong>{message}</strong>
      </p>
    </main>
  )
}
