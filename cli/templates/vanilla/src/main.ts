import "./style.css";
import viewyLogo from "./assets/viewy.svg";

const app = document.querySelector<HTMLDivElement>("#app");

if (app) {
  app.innerHTML = `
    <section class="shell">
      <img src="${viewyLogo}" class="logo" alt="viewy" />
      <p class="eyebrow">Nim backend + native webview</p>
      <h1>viewy</h1>
      <p class="lede">
        Edit <code>src/main.ts</code> for the frontend and
        <code>src/main.nim</code> for the backend.
      </p>
      <button id="ping" type="button">Ping frontend</button>
      <p id="status" class="status">Ready</p>
    </section>
  `;

  const button = document.querySelector<HTMLButtonElement>("#ping");
  const status = document.querySelector<HTMLParagraphElement>("#status");

  button?.addEventListener("click", () => {
    if (status) {
      status.textContent = `Clicked at ${new Date().toLocaleTimeString()}`;
    }
  });
}
