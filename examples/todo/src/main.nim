import std/[algorithm, sequtils, strutils]

import viewy

type
  Todo = object
    id: int
    title: string
    done: bool

var
  nextId = 1
  todos: seq[Todo]
  todoApp: App

proc sortedTodosImpl(): seq[Todo] =
  result = todos
  result.sort(proc(a, b: Todo): int = cmp(a.id, b.id))

proc emitTodosChangedImpl() =
  if todoApp != nil and todoApp.handle != nil:
    todoApp.backend.emit(todoApp.handle, "todos:changed", sortedTodosImpl())

proc listTodosSafe(): seq[Todo] {.gcsafe.} =
  {.cast(gcsafe).}:
    result = sortedTodosImpl()

proc addTodoSafe(t: Todo): seq[Todo] {.gcsafe.} =
  {.cast(gcsafe).}:
    let title = t.title.strip()
    if title.len > 0:
      let id = if t.id > 0: t.id else: nextId
      nextId = max(nextId, id + 1)
      todos.add Todo(id: id, title: title, done: t.done)
      emitTodosChangedImpl()
    result = sortedTodosImpl()

proc setTodoDoneSafe(id: int; done: bool): seq[Todo] {.gcsafe.} =
  {.cast(gcsafe).}:
    for todo in todos.mitems:
      if todo.id == id:
        todo.done = done
        emitTodosChangedImpl()
        break
    result = sortedTodosImpl()

proc deleteTodoSafe(id: int): seq[Todo] {.gcsafe.} =
  {.cast(gcsafe).}:
    todos.keepItIf(it.id != id)
    emitTodosChangedImpl()
    result = sortedTodosImpl()

expose listTodos(): seq[Todo] =
  listTodosSafe()

expose addTodo(t: Todo): seq[Todo] =
  addTodoSafe(t)

expose setTodoDone(id: int, done: bool): seq[Todo] =
  setTodoDoneSafe(id, done)

expose deleteTodo(id: int): seq[Todo] =
  deleteTodoSafe(id)

const todoHtml = """
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>viewy todo</title>
    <style>
      :root {
        color-scheme: light;
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        color: #172026;
        background: #f5f7f2;
      }

      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
      }

      main {
        width: min(680px, calc(100vw - 40px));
      }

      h1 {
        margin: 0 0 18px;
        font-size: 32px;
        font-weight: 720;
      }

      form {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 10px;
        margin-bottom: 14px;
      }

      input, button {
        height: 42px;
        border-radius: 6px;
        border: 1px solid #b9c5b6;
        font: inherit;
      }

      input {
        min-width: 0;
        padding: 0 12px;
        background: #ffffff;
      }

      button {
        padding: 0 14px;
        background: #234034;
        color: #ffffff;
        cursor: pointer;
      }

      ul {
        list-style: none;
        padding: 0;
        margin: 0;
        display: grid;
        gap: 8px;
      }

      li {
        display: grid;
        grid-template-columns: auto 1fr auto;
        gap: 10px;
        align-items: center;
        min-height: 46px;
        padding: 0 10px;
        border: 1px solid #d8ded2;
        border-radius: 8px;
        background: #ffffff;
      }

      li.done span {
        color: #6d7569;
        text-decoration: line-through;
      }

      .empty {
        margin: 18px 0 0;
        color: #68736a;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>viewy todo</h1>
      <form id="todo-form">
        <input id="todo-title" autocomplete="off" placeholder="Add a todo" aria-label="Todo title">
        <button type="submit">Add</button>
      </form>
      <ul id="todos"></ul>
      <p id="empty" class="empty">No todos yet.</p>
    </main>

    <script>
      const form = document.querySelector("#todo-form");
      const title = document.querySelector("#todo-title");
      const list = document.querySelector("#todos");
      const empty = document.querySelector("#empty");

      function render(todos) {
        list.replaceChildren();
        empty.hidden = todos.length !== 0;

        for (const todo of todos) {
          const item = document.createElement("li");
          if (todo.done) item.classList.add("done");

          const done = document.createElement("input");
          done.type = "checkbox";
          done.checked = todo.done;
          done.addEventListener("change", async () => {
            render(await window.__viewy.call("setTodoDone", todo.id, done.checked));
          });

          const text = document.createElement("span");
          text.textContent = todo.title;

          const remove = document.createElement("button");
          remove.type = "button";
          remove.textContent = "Delete";
          remove.addEventListener("click", async () => {
            render(await window.__viewy.call("deleteTodo", todo.id));
          });

          item.append(done, text, remove);
          list.append(item);
        }
      }

      window.__viewy.on("todos:changed", render);

      form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const value = title.value.trim();
        if (!value) return;
        title.value = "";
        render(await window.__viewy.call("addTodo", { id: 0, title: value, done: false }));
      });

      window.__viewy.call("listTodos").then(render);
    </script>
  </body>
</html>
"""

todoApp = newApp(title = "viewy todo", width = 720, height = 620,
    html = todoHtml)
todoApp.run()
