/**
 * Runs `deploybot env push`: local check, server dry run, confirmation, and the real push.
 *
 * The flow:
 *
 *  1. Run the local check. Missing keys stop the push unless force is true.
 *  2. Send a dry run to the server and print the diff (key names only).
 *  3. Stop here for a dry run, or when nothing changed.
 *  4. Ask for confirmation unless yes is true.
 *  5. Push for real and print each deploy step, whether the server rolled back, and the record URL.
 *
 * The server response is JSON:
 *
 *   { ok, error, dryRun, path, diff : { added, removed, changed }, missing, extra,
 *     steps : [ { id, status, summary } ], rolledBack, deployId, recordUrl }
 *
 * The error field is one of: unauthorized, locked, too_large, invalid_body, missing_keys,
 * health_failed, reinit_failed, write_failed, https_required, rate_limited, method, internal.
 * Status codes: 200 ok or dry run, 400, 401 (also for an unknown site), 403 https_required, 404
 * (an address outside DEPLOYBOT_ADMIN_ALLOWLIST gets the plain 404 page), 409 locked, 413,
 * 422 missing_keys, 429 rate limited, 500 write_failed or internal, and 502 health_failed or
 * reinit_failed.
 *
 * This component never prints the env file values or the token. It prints key names, step
 * summaries from the server, and the record URL.
 */
component extends="commandbox-deploybot.models.BaseService" {

	property name="tokenStore" inject="TokenStore@commandbox-deploybot";
	property name="envFile"    inject="EnvFile@commandbox-deploybot";
	property name="deploybotClient" inject="DeploybotClient@commandbox-deploybot";

	/**
	 * Pushes the site's env file. Throws Deploybot.* exceptions for every problem and for any
	 * non-ok result, so the command exits with an error.
	 *
	 * @config  The loaded DeploybotConfig.
	 * @force   True to push even when keys are missing.
	 * @yes     True to skip the confirmation question.
	 * @dryRun  True to show the diff and stop.
	 * @confirm A function that takes a question and returns true or false. The command supplies it.
	 */
	struct function run(
		required any config,
		boolean force   = false,
		boolean yes     = false,
		boolean dryRun  = false,
		any confirm
	){
		var config = arguments.config;
		var bytes  = variables.envFile.readBytes( config.envPath() );

		localCheck( config, arguments.force );

		var token = variables.tokenStore.get( config.host(), config.site() );
		if ( !len( token ) ) {
			fail(
				"No token is saved for site ""#config.site()#"" on #config.host()#.",
				[ "Generate a token on the site page in DeployBot (""Generate / rotate env token"").", "Then run: box deploybot token set" ],
				"What to do",
				"Deploybot.NoToken"
			);
		}

		heading( "Dry run on #config.host()# for #config.site()#..." );
		var preview = interpret(
			variables.deploybotClient.pushEnv(
				url    = config.url(),
				site   = config.site(),
				token  = token,
				body   = bytes,
				dryRun = true,
				force  = arguments.force
			)
		);
		printDiff( preview );

		if ( arguments.dryRun ) {
			say( "Dry run only. Nothing was changed on the server." );
			return preview;
		}
		var changes = changeCount( preview );
		if ( !changes ) {
			good( "No changes. The server already has these keys and values." );
			return preview;
		}
		var ask = arguments.keyExists( "confirm" ) ? arguments.confirm : "";
		if ( !arguments.yes && !confirmed( ask, "Push #changes# key change#( changes == 1 ? "" : "s" )# to #config.site()#?" ) ) {
			say( "Cancelled. Nothing was changed on the server." );
			return preview;
		}

		heading( "Pushing to #config.site()#..." );
		var result = interpret(
			variables.deploybotClient.pushEnv(
				url    = config.url(),
				site   = config.site(),
				token  = token,
				body   = bytes,
				dryRun = false,
				force  = arguments.force
			)
		);
		printSteps( result );
		if ( hasFailedStep( result ) ) {
			printRecord( result );
			stop( "The push finished with a failed step. Check the steps above and the DeployBot record.", "Deploybot.PushFailed" );
		}
		good( "Pushed. The site was reinitialized and passed its health check." );
		printRecord( result );
		return result;
	}

	/**
	 * Turns a client response into the server's result struct. It throws a Deploybot exception
	 * for every response that is not ok. When the response carries steps or missing keys, it
	 * prints them first.
	 *
	 * @response The struct from DeploybotClient: { statusCode, isJson, json }.
	 */
	struct function interpret( required struct response ){
		var status = arguments.response.statusCode;
		var data   = arguments.response.json;

		// DeployBot answers an address outside DEPLOYBOT_ADMIN_ALLOWLIST with its plain 404 page,
		// so a 404 is far more often the allowlist than a wrong URL.
		if ( status == 404 ) {
			fail(
				"DeployBot did not find the env API (HTTP 404).",
				[
					"If DEPLOYBOT_ADMIN_ALLOWLIST is set on the server, add this computer's public address to it.",
					"Check that deploybot.url in box.json points to the DeployBot server.",
					"The server may run a DeployBot version without env push."
				],
				"What to do",
				"Deploybot.NotFound"
			);
		}

		if ( !arguments.response.isJson ) {
			fail(
				"DeployBot answered with HTTP #status#, but the response was not JSON.",
				[ "Check that deploybot.url in box.json points to the DeployBot server.", "A proxy or a login page can also cause this." ],
				"What to do",
				"Deploybot.BadResponse"
			);
		}

		var success = status == 200 && isBoolean( data.ok ?: "" ) && data.ok;
		if ( success ) {
			return data;
		}

		var errorCode = data.error ?: "";
		if ( status == 401 || errorCode == "unauthorized" ) {
			fail(
				"DeployBot rejected the request: the token is wrong, or the site slug is not known.",
				[ "Check deploybot.site in box.json.", "Then run: box deploybot token set" ],
				"What to do",
				"Deploybot.Unauthorized"
			);
		}
		if ( status == 403 || errorCode == "https_required" ) {
			stop( "DeployBot only accepts env pushes over HTTPS. Change deploybot.url in box.json to https://.", "Deploybot.HttpsRequired" );
		}
		if ( status == 409 || errorCode == "locked" ) {
			stop( "Another deploy is running for this site. Wait for it to finish, then run the push again.", "Deploybot.Locked" );
		}
		if ( status == 413 || errorCode == "too_large" ) {
			stop( "DeployBot says the env file is too large. The limit is 64 KB.", "Deploybot.TooLarge" );
		}
		if ( status == 400 || errorCode == "invalid_body" ) {
			stop( "DeployBot could not read the env file (invalid_body). Check that it is plain UTF-8 text with KEY=value lines.", "Deploybot.InvalidBody" );
		}
		if ( status == 422 || errorCode == "missing_keys" ) {
			var missing = listOf( data, "missing" );
			if ( missing.len() ) {
				bad( "DeployBot reports these keys missing:" );
				for ( var key in missing ) {
					bad( "  - " & key );
				}
			}
			fail(
				"DeployBot reports #missing.len()# missing key#( missing.len() == 1 ? "" : "s" )#.",
				[ "Add the missing keys to the env file, or run again with --force to push anyway." ],
				"What to do",
				"Deploybot.MissingKeys"
			);
		}
		if ( status == 429 ) {
			stop( "DeployBot is rate limiting this client. Wait a minute and try again.", "Deploybot.RateLimited" );
		}
		if ( status == 502 || errorCode == "health_failed" || errorCode == "reinit_failed" ) {
			printSteps( data );
			printRecord( data );
			var reason = errorCode == "reinit_failed" ? "the site did not reinitialize" : "the site failed its health check";
			stop(
				"The push failed: #reason#. " & ( ( data.rolledBack ?: false ) ? "DeployBot rolled the env file back." : "DeployBot did not report a rollback. Check the site now." ),
				"Deploybot.PushFailed"
			);
		}
		if ( errorCode == "write_failed" ) {
			printSteps( data );
			printRecord( data );
			stop( "The push failed: DeployBot could not write the env file.", "Deploybot.PushFailed" );
		}
		if ( status == 500 ) {
			stop( "DeployBot hit an internal error (#len( errorCode ) ? errorCode : "HTTP 500"#). Nothing was written. Check DeployBot's log.", "Deploybot.ServerError" );
		}
		if ( len( errorCode ) ) {
			stop( "DeployBot reported an error: #errorCode# (HTTP #status#).", "Deploybot.Http" );
		}
		stop( "DeployBot answered with an unexpected result (HTTP #status#).", "Deploybot.Http" );
	}

	/**
	 * Runs the local check and stops on missing keys unless force is true. With force, a missing
	 * .env.example or missing keys become warnings.
	 *
	 * @config The loaded DeploybotConfig.
	 * @force  True to continue after a failed check.
	 */
	private void function localCheck( required any config, required boolean force ){
		var checker = service( "EnvChecker" );
		var result  = {};
		try {
			result = checker.report( arguments.config );
		} catch ( any exception ) {
			if ( ( exception.type ?: "" ) != "Deploybot.NoExample" || !arguments.force ) {
				rethrow;
			}
			warn( "Skipping the local check because of --force: " & exception.message );
			return;
		}
		if ( result.missing.len() ) {
			if ( !arguments.force ) {
				stop( "#result.missing.len()# key#( result.missing.len() == 1 ? "" : "s" )# from .env.example #( result.missing.len() == 1 ? "is" : "are" )# missing. Fix the env file or use --force.", "Deploybot.MissingKeys" );
			}
			warn( "Continuing with missing keys because of --force." );
		}
	}

	/**
	 * Asks the confirmation question through the function the command supplied. Without one,
	 * the push stops, because a push must not run without an answer.
	 *
	 * @ask      The confirmation function, or an empty string when the caller gave none.
	 * @question The question to ask.
	 */
	private boolean function confirmed( required any ask, required string question ){
		if ( !isCustomFunction( arguments.ask ) ) {
			stop( "A confirmation is needed. Use --yes to skip it.", "Deploybot.Stop" );
		}
		return arguments.ask( arguments.question );
	}

	/**
	 * Returns true when any step in the result has the status "failed".
	 *
	 * @data The result struct from the server.
	 */
	private boolean function hasFailedStep( required struct data ){
		var steps = arguments.data.steps ?: [];
		if ( isArray( steps ) ) {
			for ( var step in steps ) {
				if ( isStruct( step ) && ( step.status ?: "" ) == "failed" ) {
					return true;
				}
			}
		}
		return false;
	}

	/**
	 * Prints the dry-run diff: key names the push would add, remove, or change, and the keys the
	 * server reports as missing or extra.
	 *
	 * @data The result struct from the server.
	 */
	private void function printDiff( required struct data ){
		// The server picks the site's webroot .env if one exists, else the one above the webroot.
		// Show which, so a stray webroot file is noticed before it is overwritten.
		var target = arguments.data.path ?: "";
		if ( isSimpleValue( target ) && len( target ) ) {
			say( "Target file on the server: #target#" );
		}
		var diff = arguments.data.diff ?: {};
		for ( var entry in [
			{ name : "added", mark : "+", label : "Added" },
			{ name : "removed", mark : "-", label : "Removed" },
			{ name : "changed", mark : "~", label : "Changed" }
		] ) {
			var keys = listOf( diff, entry.name );
			if ( keys.len() ) {
				say( "#entry.label# (#keys.len()#):" );
				for ( var key in keys ) {
					say( "  #entry.mark# #key#" );
				}
			}
		}
		if ( !changeCount( arguments.data ) ) {
			say( "No key changes." );
		}
		var missing = listOf( arguments.data, "missing" );
		if ( missing.len() ) {
			warn( "Server reports missing keys: " & missing.toList( ", " ) );
		}
		var extra = listOf( arguments.data, "extra" );
		if ( extra.len() ) {
			say( "Server reports extra keys: " & extra.toList( ", " ) );
		}
	}

	/**
	 * Returns how many key names the diff adds, removes, or changes.
	 *
	 * @data The result struct from the server.
	 */
	private numeric function changeCount( required struct data ){
		var diff  = arguments.data.diff ?: {};
		return listOf( diff, "added" ).len() + listOf( diff, "removed" ).len() + listOf( diff, "changed" ).len();
	}

	/**
	 * Prints each deploy step with its id, status, and summary, then the rollback state.
	 *
	 * @data The result struct from the server.
	 */
	private void function printSteps( required struct data ){
		var steps = arguments.data.steps ?: [];
		if ( isArray( steps ) ) {
			for ( var step in steps ) {
				if ( !isStruct( step ) ) {
					continue;
				}
				var line = "  [#step.status ?: "?"#] #step.id ?: "?"# - #step.summary ?: ""#";
				switch ( step.status ?: "" ) {
					case "success":
						good( line );
						break;
					case "warning":
						warn( line );
						break;
					case "failed":
						bad( line );
						break;
					default:
						say( line );
				}
			}
		}
		if ( arguments.data.keyExists( "rolledBack" ) && isBoolean( arguments.data.rolledBack ) ) {
			if ( arguments.data.rolledBack ) {
				warn( "Rolled back: the previous env file is back in place." );
			} else {
				say( "Rolled back: no" );
			}
		}
	}

	/**
	 * Prints the deploy record URL when the server sent one.
	 *
	 * @data The result struct from the server.
	 */
	private void function printRecord( required struct data ){
		if ( len( arguments.data.recordUrl ?: "" ) ) {
			say( "Record: " & arguments.data.recordUrl );
		}
	}

	/**
	 * Returns a list of key names from a struct. Anything but an array of text gives an empty array.
	 *
	 * @source The struct that holds the array.
	 * @name   The key of the array.
	 */
	private array function listOf( required struct source, required string name ){
		var keys = [];
		if ( arguments.source.keyExists( arguments.name ) && isArray( arguments.source[ arguments.name ] ) ) {
			for ( var item in arguments.source[ arguments.name ] ) {
				if ( isSimpleValue( item ) ) {
					keys.append( item );
				}
			}
		}
		return keys;
	}
}
