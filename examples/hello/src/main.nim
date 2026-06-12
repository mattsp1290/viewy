import viewy

expose greet(name: string): string =
  "Hello, " & name & " from Nim!"

newApp(title = "viewy hello").run()
