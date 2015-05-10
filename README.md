# json.pony

A toy JSON parser for [Pony](http://ponylang.org).

## Synopsis

```
use "json"

actor Main
  new create(env: Env) =>
    var valid_input : String = "{\"yes\": 34.6, \"no\": 45, \"maybe\": [\"ok\", 1]}"
    env.out.print("Input: " + valid_input)

    var json : JSON.parse(valid_input)
  
    match json.value()
    | (JObject, m : Map[String, JSON] box) =>
      try match m("maybe")
      | (JArray, l : List[JSON]) =>
        try match m(0)
        | (JString, s : String) => env.out.print("Value of .maybe[0]: " + s
        end end
      end end
    end

    var invalid_input : String = "{\"numbers\": [1, 2, 3"

    match JSON.parse(invalid_input).value()
    | (ParseError, var pos : U64, var message : String) =>
      env.out.print("Invalid JSON: \"" + message + "\" at character " + pos.string())
    end

    env.out.print("Formatted: " + json.stringify(env))
```

## Caveats

This only parses strings, it *should* be changed to parse ReadSeqs of
characters. (maybe Streams? I don't know enough Pony to tell yet)

## License

[MIT](LICENSE)
