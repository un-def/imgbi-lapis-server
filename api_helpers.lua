local respond_to = require('lapis.application').respond_to

local is_uppercase = require('utils').is_uppercase


-- lapis.application.yield_error with optional status code
local function yield_err(msg, status)
  local error
  if status then
    error = {msg, status}
  else
    error = msg
  end
  return coroutine.yield('error', {error})
end

-- lapis.application.assert_error with optional status code
local function assert_err(thing, msg, status, ...)
  if not thing then yield_err(msg, status) end
  return thing, msg, status, ...
end


local methods_table_meta = {
  __index = function(tbl, key)
      if is_uppercase(key) then
        return tbl.method_not_allowed_handler
      end
  end
}

local function on_error_handler(self)
  --[[
  in action:
  yield_err('foo') -> {"status": "error", "err": "foo"} with 500 code
  yield_err('foo', 403) -> {"status": "error", "err": "foo"} with 403 code
  or (with same result):
  assert_err(func(arg1, arg2), 'foo')
  assert_err(func(arg1, arg2), 'foo', 403)
  ]]
  local error = self.errors[1]
  local err, status
  if type(error) == 'table' then
    err = error[1]
    status = error[2]
  else
    err = error
    status = 500
  end
  return {
    status = status,
    json = {
      status = 'error',
      err = err,
    }
  }
end

local function api_methods(methods_table)
  local methods = {}
  for key, _ in pairs(methods_table) do
    if is_uppercase(key) then
      table.insert(methods, key)
    end
  end

  methods_table.method_not_allowed_handler = function()
    return {
      status = 405,
      content_type = 'text/plain',
      headers = {
        Allow = table.concat(methods, ', ')
      },
      '405 Method Not Allowed'
    }
  end

  setmetatable(methods_table, methods_table_meta)
  return respond_to(methods_table)
end


local api_meta
api_meta = {
  __call = function(_, app, api_entry_point, on_error)
    local instance = {
      app = app,
      api_entry_point = api_entry_point,
      on_error = on_error or on_error_handler,
    }
    return setmetatable(instance, api_meta)
  end
  ,
  __index = {
    route = function(self, route_name, path, methods_table)
      if path == '/' then
        path = self.api_entry_point
      else
        path = self.api_entry_point .. path
      end
      if not methods_table.on_error then
        methods_table.on_error = self.on_error
      end
      self.app:match(route_name, path, api_methods(methods_table))
    end
  }
}

local Api = setmetatable({}, api_meta)


return {
  Api = Api,
  yield_err = yield_err,
  assert_err = assert_err,
}
