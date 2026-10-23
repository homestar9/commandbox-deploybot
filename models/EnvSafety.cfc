/**
 * Checks where the env file lives on this computer. `env check`, `env push`, and `init` use it.
 *
 *  - A file that git tracks is an error. Its values are already in the repository history.
 *  - A file in a git repository that .gitignore does not cover is a warning. One `git add .`
 *    would commit it.
 *  - A file in a folder that a cloud service syncs (Dropbox, OneDrive, iCloud Drive, Google
 *    Drive) is a warning. The service keeps a copy of the secrets on its servers.
 *
 * It never reads the file. It prints the file name only.
 */
component extends="commandbox-deploybot.models.BaseService" {

	property name="gitInspector" inject="GitInspector@commandbox-deploybot";

	/**
	 * Folder names that cloud services sync, matched against each folder in a path, in lower case.
	 * A folder also matches when a space and more text follow the name, such as
	 * "OneDrive - Contoso" or "Dropbox (Personal)".
	 */
	variables.syncedFolders = [
		{ prefix : "dropbox", service : "Dropbox" },
		{ prefix : "onedrive", service : "OneDrive" },
		{ prefix : "icloud drive", service : "iCloud Drive" },
		{ prefix : "iclouddrive", service : "iCloud Drive" },
		{ prefix : "com~apple~clouddocs", service : "iCloud Drive" },
		{ prefix : "google drive", service : "Google Drive" },
		{ prefix : "googledrive", service : "Google Drive" },
		{ prefix : "my drive", service : "Google Drive" }
	];

	/**
	 * Checks the env file and prints what it finds. Returns { tracked, ignored, repository,
	 * syncedBy }. syncedBy is the name of the cloud service, or an empty string.
	 *
	 * @config The loaded DeploybotConfig.
	 */
	struct function check( required any config ){
		var path   = arguments.config.envPath();
		var name   = arguments.config.envFile();
		var git    = variables.gitInspector.status( path );
		var result = {
			tracked    : git.known && git.tracked,
			ignored    : git.known && git.ignored,
			repository : git.known && git.repository,
			syncedBy   : syncedBy( path )
		};

		if ( result.tracked ) {
			bad( "#name# is tracked by git. Its values are in the repository history." );
			bad( "  1. Remove it from git, but keep the file: git rm --cached #name#" );
			bad( "  2. Add it to .gitignore. box deploybot init does this." );
			bad( "  3. Change every secret in it. The old values stay in the history." );
		} else if ( result.repository && !result.ignored ) {
			warn( "#name# is not covered by .gitignore. Run box deploybot init, or add it to .gitignore." );
		}
		if ( len( result.syncedBy ) ) {
			warn( "#name# is in a #result.syncedBy# folder. #result.syncedBy# keeps a copy of its secrets in the cloud." );
			warn( "  To keep it on this computer only, set deploybot.envFile in box.json to a path outside synced folders." );
		}
		return result;
	}

	/**
	 * Returns the name of the cloud service that syncs a path, or an empty string.
	 *
	 * @path A full path.
	 */
	string function syncedBy( required string path ){
		for ( var folder in replace( arguments.path, "\", "/", "all" ).listToArray( "/" ) ) {
			var lower = lCase( trim( folder ) );
			for ( var entry in variables.syncedFolders ) {
				if ( lower == entry.prefix || left( lower, len( entry.prefix ) + 1 ) == entry.prefix & " " ) {
					return entry.service;
				}
			}
		}
		return "";
	}
}
