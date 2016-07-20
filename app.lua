local lapis = require('lapis')
local config = require('lapis.config').get()

local api_helpers = require('api_helpers')
local Api = api_helpers.Api
local assert_err = api_helpers.assert_err
local utils = require('utils')
local errors = require('errors')


local app = lapis.Application()
app.layout = false
local api = Api(app, config.api_entry_point)


api:route('upload', '/upload', {
  POST = function(self)
    local host = self.req.parsed_url.host
    if host:match('%.onion$') or host:match('%.i2p$') then
      assert_err(utils.check_hidden_limit(), errors.hidden_limit, 403)
    else
      local ip = assert_err(utils.get_client_ip(self), errors.server_error)
      assert_err(utils.check_ip_limit(ip), errors.ip_limit, 403)
    end

    local post = self.req.params_post
    local expire = post.expire

    if expire then
      assert_err(utils.is_int(expire), errors.invalid_expire, 400)
      expire = tonumber(expire) * 86400 + os.time()
    end

    assert_err(
      utils.check_encrypted(post.encrypted), errors.invalid_encrypted, 400)
    if post.thumb then
      assert_err(utils.check_encrypted(post.thumb), errors.invalid_thumb, 400)
    end

    local id = assert_err(utils.get_id(), errors.db_error)

    assert_err(utils.save_image(id, post.encrypted), errors.failed_to_write)
    if post.thumb then
      assert_err(utils.save_thumb(id, post.thumb), errors.failed_to_write)
    end

    local pass = utils.generate_password()
    local hash = utils.hash_password(pass)

    assert_err(utils.store_values(id, hash, expire), errors.db_error)

    return {
      json = {
        status = 'OK',
        id = id,
        pass = pass,
      }
    }
  end
})


api:route('remove', '/remove', {
  -- yes, we execute UNSAFE idempotent action with GET method
  -- it should be fixed in frontend
  GET = function(self)
    local id = self.req.params_get.id
    local pass = self.req.params_get.password
    assert_err(utils.is_alphanumeric(id), errors.invalid_request_id, 400)
    assert_err(utils.is_alphanumeric(pass), errors.invalid_request_pass, 400)

    local hash = assert_err(utils.retrieve_hash(id), errors.db_error)
    assert_err(hash ~= '', errors.no_file)
    assert_err(utils.check_password(pass, hash), errors.invalid_password, 403)

    assert_err(utils.remove_image(id), errors.failed_to_remove)
    assert_err(utils.remove_thumb(id), errors.failed_to_remove)
    assert_err(utils.delete_id(id), errors.db_error)

    return {
      json = {
        status = 'OK',
      }
    }
  end
})


app.handle_404 = function()
  return {
    status = 404,
    content_type = 'text/plain',
    '404 Not Found'
  }
end


app.handle_error = function(self, err, trace)
  if config._name == 'development' then
    return lapis.Application.handle_error(self, err, trace)
  end
  return {
    status = 500,
    content_type = 'text/plain',
    '500 Internal Server Error'
  }
end


return app
