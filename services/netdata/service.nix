#   services.netdata.enable = true;
#   services.netdata.configDir = {
#     "stream.conf" = pkgs.writeText "stream.conf" ''
#       [UUID]
#         enabled = yes
#         default history = 3600
#         default memory mode = dbengine
#         health enabled by default = auto
#         allow from = 10.*
#     '';
#   };
