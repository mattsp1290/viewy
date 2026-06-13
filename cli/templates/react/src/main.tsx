import "./style.css";
import { StrictMode, useState } from "react";
import { createRoot } from "react-dom/client";
import viewyLogo from "./assets/viewy.svg";

const app = document.querySelector<HTMLDivElement>("#app");

if (!app) {
  throw new Error("Missing #app mount point");
}

function App() {
  const [status, setStatus] = useState("Ready");

  return (
    <section className="shell">
      <img src={viewyLogo} className="logo" alt="viewy" />
      <p className="eyebrow">React frontend + Nim backend</p>
      <h1>viewy</h1>
      <p className="lede">
        Edit <code>src/main.tsx</code> for the frontend and{" "}
        <code>src/main.nim</code> for the backend.
      </p>
      <button
        type="button"
        onClick={() => setStatus(`Clicked at ${new Date().toLocaleTimeString()}`)}
      >
        Ping frontend
      </button>
      <p className="status">{status}</p>
    </section>
  );
}

createRoot(app).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
