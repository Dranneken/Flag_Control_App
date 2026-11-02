local ffi = require('ffi')
local windowsCrypto = {}

ffi.cdef[[
typedef unsigned char FCA_UCHAR;
typedef unsigned long FCA_ULONG;
typedef long FCA_NTSTATUS;
FCA_NTSTATUS __stdcall BCryptGenRandom(
  void *algorithm,
  FCA_UCHAR *buffer,
  FCA_ULONG bufferLength,
  FCA_ULONG flags
);
]]

local bcrypt = ffi.load('bcrypt')

function windowsCrypto.randomBytes(length)
  if type(length) ~= 'number' or length < 1 or length > 1024 or
     length ~= math.floor(length) then
    return nil, 'invalid_length'
  end

  local buffer = ffi.new('FCA_UCHAR[?]', length)
  local status = bcrypt.BCryptGenRandom(nil, buffer, length, 2)
  if status ~= 0 then return nil, 'crypto_unavailable' end
  return ffi.string(buffer, length)
end

return windowsCrypto
