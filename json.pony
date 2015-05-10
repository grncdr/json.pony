use "collections"

primitive JNull
primitive JNumber
primitive JString
primitive JObject
primitive JArray
primitive ParseError

type JType is (JObject | JNumber | JString | JArray | JNull)

type JSONValue is ( JNull
                  | (JNumber, Number)
                  | (JString, String)
                  | (JObject, Map[String, JSON] box)
                  | (JArray, List[JSON] box)
                  | (ParseError, U64, String) )

class JSON
  var _value : JSONValue
  var _input : String box
  var _offset : U64
  var _must_complete : Bool

  new parse(input: String box,
            offset: U64 = 0,
            must_complete: Bool = true) =>
    _value = (ParseError, U64(0), "Parser never started")
    _input = input
    _offset = offset
    _must_complete = must_complete

    _skip_whitespace()

    _value = match _current()
    | 'n' => _parse_null()
    | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
      _parse_number()
    | '"' => _parse_string()
    | '{' => _parse_object()
    | '[' => _parse_array()
    else _unexpected_character() end

    match _value
    | (ParseError, _, _) => None
    else
      _skip_whitespace()

      if must_complete and (_offset < _input.size()) then
        _value = _parse_error("Only consumed " + _offset.string() +
                              " of " + input.size().string() + " bytes")
      end
    end

  fun value(): box->JSONValue =>
    _value

  fun _peek_offset(): U64 =>
    _offset

  fun ref _reset(i: U64) =>
    _offset = i

  fun _current(): U8 =>
    try
      _input(_offset)
    else
      '\0'
    end

  fun ref _advance(n: U64 = 1) =>
    _offset = _offset + n

  fun ref _no_more_input(): Bool =>
    _offset >= _input.size()

  fun ref _consume_comma() =>
    if _current() == ',' then
      _advance()
      _skip_whitespace()
    end

  fun ref _skip_whitespace() =>
    while _offset < _input.size() do
      match _current() | ' ' | '\v' | '\t' | '\n' | '\r' =>
        _advance()
      else
        break
      end
    end

  fun ref _recurse(): JSON =>
    JSON.parse(_input, _offset, false)

  fun ref _parse_error(message : String = "Parse error", offset: (None | U64) = None): JSONValue =>
    (ParseError,
     match offset | var o: U64 => o else _offset end,
     message)

  fun ref _unexpected_character(): JSONValue =>
    _parse_error("Unexpected character " + _current().string())

  fun ref _expected_character(char: U8): JSONValue =>
    _parse_error("Expected a '" + char.string() + "'")

  fun ref _parse_null(): JSONValue => 
    if _input.at("null", _offset.i64()) then
      _advance(4)
      JNull
    else
      _parse_error()
    end

  fun ref _parse_number(): JSONValue =>
    var divisor : I32 = 0
    var n : I64 = 0
    while _offset < _input.size() do
      var n' = _current().i64() - 48
      if (n' == -2) and (divisor == 0) then
        divisor = 1
      elseif (n' < 0) or (n' > 9) then
        break
      else
        n = (n * 10) + n'
        if divisor > 0 then
          divisor = divisor * 10
        end
      end

      _advance()
    end

    (JNumber, if divisor == 0 then n else (n.f64() / divisor.f64()) end)

  fun ref _parse_string(): JSONValue =>
    if _current() == '"' then
      _advance()
    else
      return _parse_error("Attempted to parse a string here")
    end

    var escape : Bool = false
    var s : String ref = String(1024)
    var string_start : U64 = _offset

    while true do
      if _offset == _input.size() then
        return _parse_error("Unclosed string literal", string_start)
      elseif escape then
        escape = false
        s.push(_current())
      elseif _current() == '\\' then
        escape = true
      elseif _current() == '"' then
        _advance()
        break
      else
        s.push(_current())
      end
      _advance()
    end

    (JString, s.clone())

  fun ref _parse_array(): JSONValue =>
    if _current() == '[' then
      _advance()
      _skip_whitespace()
    else
      return _parse_error("Tried to parse '" + _current().string() + "' as array")
    end

    var array_start = _offset
    var list = List[JSON](0)

    while true do
      match (_no_more_input(), _current())
      | (true, _) =>
        return _parse_error("Unclosed array", array_start)
      | (false, ']') =>
        _advance()
        break
      end

      let item = _recurse()
      let v = item.value()

      match v
      | (ParseError, _, _) => return v
      else
        _reset(item._peek_offset())
        list.push(item)
      end
      _consume_comma()
    end
    (JArray, list)

  fun ref _parse_object(): JSONValue =>
    if _current() == '{' then
      _advance()
      _skip_whitespace()
    else
      return _parse_error("Expected an object")
    end

    var map = Map[String, JSON]()
    var object_start = _offset

    while true do
      match (_no_more_input(), _current())
      | (true, _) =>
        return _parse_error("Unclosed object", object_start)
      | (false, '}') =>
        _advance()
        break
      | (false, '"') =>
        None
      else
        return _parse_error("Expected a string")
      end

      let key : JSON = _recurse()

      _reset(key._peek_offset())

      match (key.value(), _current())
      | ((ParseError, _, _), _) =>
        return key.value()
      | ((JString, var s: String), ':') =>
        _advance()
        let value' : JSON = _recurse()

        match value'.value()
        | (ParseError, _, _) =>
          return value'.value()
        else
          _reset(value'._peek_offset())
          map.update(s, value')
        end
      | ((JString, _), _) =>
        return _expected_character(':')
      else
        return _parse_error("Key is not a string")
      end

      if _current() == ',' then
        _advance()
        _skip_whitespace()
      end
    end
    (JObject, map)

  fun box stringify(indent: U8 = 0): String =>
    JSONFormatter(indent)(_value)


class JSONFormatter
  var _indent : String
  var _kv_sep : String = ":"


  new create(indent : U8 = 0) =>
    _indent = ""
    var i = indent
    while i > 0 do
      _indent = _indent + " "
      i = i - 1
    end
    if indent > 0 then
      _kv_sep = ": "
    end

  fun apply(value: JSONValue): String =>
    _format(value)

  fun _format(value: JSONValue, indent : String = ""): String =>
    match value
    | (ParseError, var pos: U64, var msg: String) => "Error at position " + pos.string() + ": " + msg
    | JNull => "null"
    | (JNumber, var n : U64) => n.string()
    | (JNumber, var n : I64) => n.string()
    | (JNumber, var n : F32) => n.string()
    | (JNumber, var n : F64) => n.string()
    | (JString, var s : String) => _quote_string(s)
    | (JArray,  var list : box->List[JSON] box) =>
      var items = Array[String](list.size())
      for item in list.values() do
        items.push(_format(item.value(), indent + _indent))
      end
      "[" + _join(items, indent) + "]"
    | (JObject, var map : box->Map[String, JSON] box) =>
      var items = Array[String](map.size())
      for (k, v) in map.pairs() do
        items.push(_quote_string(k) + _kv_sep + _format(v.value(), indent + _indent))
      end
      "{" + _join(items, indent) + "}"
    else
      "Unknown json type"
    end

  fun _join(strings: Array[String], indent: String): String =>
    let nli = if _indent.size() > 0 then "\n" + indent + _indent else _indent end
    let glue = "," + nli
    var out = nli
    var iter = strings.values()
    for string in iter do
      out = out + string + if iter.has_next() then glue else "" end
    end
    out + "\n" + indent

  fun _quote_string(string: String): String =>
    "\"" + string + "\""


// TODO - figure out ponytest
actor Main
  new create(env: Env) =>
    var valid_input : String = "{\"yes\": 34.6, \"no\": 45, \"maybe\": [\"ok\", 1]}"
    env.out.print("Input: " + valid_input)

    var json = JSON.parse(valid_input)

    match json.value()
    | (JObject, var map : Map[String, JSON] box) =>
      match try map("maybe").value() end
      | (JArray, var list : List[JSON] box) =>
        match try list(0).value() end
        | (JString, var str : String) =>
          env.out.print("Value of .maybe[0]: " + str)
        end
      end
    end

    env.out.print("Formatted: " + json.stringify(1))

    var invalid_input : String = "{\"numbers\": [1, 2, 3"

    match JSON.parse(invalid_input).value()
    | (ParseError, var pos : U64, var message : String) =>
      env.out.print("Invalid JSON: " + message + " at character " + pos.string())
    end

