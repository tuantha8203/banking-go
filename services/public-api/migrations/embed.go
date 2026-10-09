// Package migrations embeds public-api's goose SQL migrations (database "public", AD-3). Empty until
// the first feature adds <version>_<name>.sql here; `public-api migrate up` is then a no-op.
package migrations

import "embed"

// FS holds this directory; migrate.Up reads only *.sql at its root.
//
//go:embed *
var FS embed.FS
