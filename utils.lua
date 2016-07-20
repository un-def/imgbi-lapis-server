local config = require('lapis.config').get()
local get_redis = require('lapis.redis').get_redis
local cjson = require('cjson.safe')
local random = require('resty.random')
local hashids = require('hashids')
local bcrypt = require('bcrypt')
local basex = require('basex')

local B62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
local base62 = basex(B62)

local BCRYPT_LOG_ROUNDS = 10


local function is_non_empty_string(str)
  return type(str) == 'string' and #str > 0
end

local function is_uppercase(str)
  return is_non_empty_string(str) and not str:match('%U')
end

local function is_alphanumeric(str)
  return is_non_empty_string(str) and not str:match('%W')
end

local function is_int(str)
  return is_non_empty_string(str) and not str:match('%D')
end


local function get_id()
  local redis, err = get_redis()
  if err then return nil, err end
  local res
  res, err = redis:incr('imgbi:next_file_id')
  if err then return nil, err end
  return hashids.new(config.hashids):encode(res)
end


local function check_encrypted(content)
  local dec, err = cjson.decode(content)
  if err then return nil, 'notJSON' end
  if type(dec) == 'table' and dec.iv then return true end
  return nil, 'invalidJSON'
end


local function generate_password()
  local strong_random
  while not strong_random do
    strong_random = random.bytes(40, true)
  end
  return base62:encode(strong_random)
end


local function hash_password(password)
  return bcrypt.digest(password, BCRYPT_LOG_ROUNDS)
end


-- unfortunately, `io` module is BLOCKING
-- TODO: reimplement save_* functions with nonblocking file I/O

local function save_file(filename, content)
  local file, err = io.open(filename, 'w')
  if err then error(err) end
  file:write(content)
  file:close()
end

local function save_image(id, content)
  local filename = config.upload_images_dir .. '/' .. id
  return pcall(save_file, filename, content)
end

local function save_thumb(id, content)
  local filename = config.upload_thumbs_dir .. '/' .. id
  return pcall(save_file, filename, content)
end


local function remove_file(filename)
  local _, err = os.remove(filename)
  if not err or err:match('No such file') then return true end
  error(err)
end

local function remove_image(id)
  local filename = config.upload_images_dir .. '/' .. id
  return pcall(remove_file, filename)
end

local function remove_thumb(id)
  local filename = config.upload_thumbs_dir .. '/' .. id
  return pcall(remove_file, filename)
end


local function store_values(id, hash, expire)
  -- store hash and (optional) expire for image id in Redis
  local redis, err, _
  redis, err = get_redis()
  if err then return nil, err end
  if expire then
    _, err = redis:multi()
    if err then return nil, err end
    _, err = redis:zadd('imgbi:expire', expire, id)
    if err then return nil, err end
  end
  _, err = redis:set('imgbi:file:' .. id, hash)
  if err then return nil, err end
  if expire then
    _, err = redis:exec()
    if err then return nil, err end
  end
  return true
end


local function retrieve_hash(id)
  -- get password hash from Redis by image id
  -- return empty string if id not found
  local redis, err, hash
  redis, err = get_redis()
  if err then return nil, err end
  hash, err = redis:get('imgbi:file:' .. id)
  if err then return nil, err end
  if hash == ngx.null then return '' end
  return hash
end


local function delete_id(id)
  -- delete image id from Redis
  local redis, err, _
  redis, err = get_redis()
  if err then return nil, err end
  _, err = redis:del('imgbi:file:' .. id)
  if err then return nil, err end
  return true
end


local function check_password(password, hash)
  return bcrypt.verify(password, hash)
end


local function get_client_ip(request)
  if config.client_ip_header then
    return request.req.headers[config.client_ip_header]
  end
    return ngx.var.remote_addr
end


local function check_ip_limit(ip)
  return true
end


local function check_hidden_limit()
  return true
end


return {
  is_uppercase = is_uppercase,
  is_alphanumeric = is_alphanumeric,
  is_int = is_int,
  get_id = get_id,
  check_encrypted = check_encrypted,
  generate_password = generate_password,
  hash_password = hash_password,
  save_image = save_image,
  save_thumb = save_thumb,
  remove_image = remove_image,
  remove_thumb = remove_thumb,
  store_values = store_values,
  retrieve_hash = retrieve_hash,
  delete_id = delete_id,
  check_password = check_password,
  get_client_ip = get_client_ip,
  check_ip_limit = check_ip_limit,
  check_hidden_limit = check_hidden_limit,
}
