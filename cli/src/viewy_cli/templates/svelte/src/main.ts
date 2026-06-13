import "./style.css";
import { mount } from "svelte";
import App from "./App.svelte";

const app = document.querySelector<HTMLDivElement>("#app");

if (!app) {
  throw new Error("Missing #app mount point");
}

mount(App, {
  target: app,
});
