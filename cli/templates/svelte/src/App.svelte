<script lang="ts">
  import viewyLogo from "./assets/viewy.svg";

  let status = "Ready";
</script>

<section class="shell">
  <img src={viewyLogo} class="logo" alt="viewy" />
  <p class="eyebrow">Svelte frontend + Nim backend</p>
  <h1>viewy</h1>
  <p class="lede">
    Edit <code>src/App.svelte</code> for the frontend and
    <code>src/main.nim</code> for the backend.
  </p>
  <button
    type="button"
    on:click={() => {
      status = `Clicked at ${new Date().toLocaleTimeString()}`;
    }}
  >
    Ping frontend
  </button>
  <p class="status">{status}</p>
</section>
