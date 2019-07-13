defmodule Absinthe.Guards do
  defguard is_jpg(value) when binary_part(value, 0, 2) == <<0xFF, 0xD8>>

  defguard is_jfif(vale)
           when binary_part(value, 0, 14) ==
                  <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01,
                    0x00>>
end