## Asset strategy knobs for the high-level app API.

type
  AssetMode* = enum
    ## Load a self-contained HTML document directly with the backend.
    assetsEmbedded
    ## Navigate to a development server URL.
    assetsDevServer
