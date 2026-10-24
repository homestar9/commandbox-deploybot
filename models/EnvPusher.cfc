/**
 * Runs `deploybot env push`: local check, server dry run, confirmation, and the real push.
 *
 * The flow:
 *
 *  1. Run the local check. A file that git tracks or missing keys stop the push unless force is
 *     true. A file outside .gitignore gets a warning.
 *  2. Send a dry run to the server and print the diff (key names only).
 *  3. Stop here for a dry run, or when nothing changed.
 *  4. Ask for confirmation unless yes is true.
 *  5. Push for real and print each deploy step, whether the server rolled back, and the record URL.
 *     The push asks for async: a server that supports it answers 202 at once, and the push is
 *     followed live (follow()): each step's result as it ends, a line when the reload and the
 *     health check start, and every health attempt and retry. An older server answers when the
 *     push has finished, and the steps print all at once.
 *
 * The server response is DeployBot's API envelope, { data, error, messages }. For a push, data is:
 *
 *   { ok, errorCode, dryRun, path, diff : { added, removed, changed }, missing, extra,
 *     steps : [ { id, status, summary } ], rolledBack, healthyBefore, queued, deployId, recordUrl }
 *
 * A refusal carries only { errorCode } in data. errorCode is one of: unauthorized, locked,
 * too_large, invalid_body, missing_keys, health_failed, reinit_failed, site_down, write_failed,
 * https_required, rate_limited, method, not_found, internal. messages says it in words.
 * Status codes: 200 ok or dry run, 202 accepted (async), 400, 401 (also for an unknown site), 403
 * https_required, 404 (no such API address; an address outside DEPLOYBOT_ADMIN_ALLOWLIST gets the
 * plain 404 page), 405, 409 locked, 413, 422 missing_keys, 429 rate limited, 500 write_failed or
 * internal, and 502 health_failed, reinit_failed or site_down (the site was failing before the
 * push, so the server kept the new file).
 *
 * This component never prints the env file values or the token. It prints key names, step
 * summaries from the server, and the record URL.
 */
component extends="commandbox-deploybot.models.BaseService" {

	property name="tokenStore" inject="TokenStore@commandbox-deploybot";
	property name="envFile"    inject="EnvFile@commandbox-deploybot";
	property name="deploybotClient" inject="DeploybotClient@commandbox-deploybot";

	/** How long to wait between progress requests while following a push, in milliseconds. */
	variables.pollMs = 1000;
	/** Progress requests in a row that may fail before the push is given up on. */
	variables.maxPollFailures = 5;
	/** How long a push is followed at most, in seconds (the server allows a push 15 minutes). */
	variables.maxWaitSeconds = 900;

	/**
	 * Sets the wait between progress requests. Specs set 0.
	 *
	 * @ms Milliseconds.
	 */
	function setPollMs( required numeric ms ){
		variables.pollMs = arguments.ms;
		return this;
	}

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
		var response = variables.deploybotClient.pushEnv(
			url    = config.url(),
			site   = config.site(),
			token  = token,
			body   = bytes,
			dryRun = false,
			force  = arguments.force,
			async  = true
		);
		// 202: the server runs the push and is followed live. An older server ignores async and
		// answers when the push has finished, with every step at once.
		var followed = response.statusCode == 202 && response.isJson && isStruct( response.json.data ?: "" );
		var result   = followed ? interpret( asResponse( follow( config, token, response.json.data ) ), true ) : interpret( response );
		if ( followed ) {
			printRollback( result );
		} else {
			printSteps( result );
		}
		if ( hasFailedStep( result ) ) {
			printRecord( result );
			stop( "The push finished with a failed step. Check the steps above and the DeployBot record.", "Deploybot.PushFailed" );
		}
		printOutcome( result );
		printRecord( result );
		return result;
	}

	/**
	 * Follows a push the server accepted with 202 until it ends. It prints as the push goes: a
	 * line when a slow step starts, every health attempt and retry, and each step's result, in
	 * order. Returns the result struct a server that does not follow would have answered with.
	 *
	 * @config   The loaded DeploybotConfig.
	 * @token    The env token.
	 * @accepted The 202 answer's data: { queued, deployId, recordUrl }.
	 */
	private struct function follow( required any config, required string token, required struct accepted ){
		var id        = toString( arguments.accepted.deployId ?: "" );
		var recordUrl = toString( arguments.accepted.recordUrl ?: "" );
		var where     = len( recordUrl ) ? recordUrl : "the site's history in DeployBot";
		if ( !len( id ) ) {
			stop( "DeployBot accepted the push but sent no record id to follow. Check the site's history in DeployBot.", "Deploybot.BadResponse" );
		}
		var state    = { offset : 0, shown : {} };
		var failures = 0;
		var started  = getTickCount();
		var data     = {};
		while ( true ) {
			if ( ( getTickCount() - started ) / 1000 > variables.maxWaitSeconds ) {
				stop( "DeployBot has run the push for more than #int( variables.maxWaitSeconds / 60 )# minutes. It may still be running; see #where#.", "Deploybot.Timeout" );
			}
			if ( variables.pollMs > 0 ) {
				sleep( variables.pollMs );
			}
			var answer = {};
			try {
				answer = variables.deploybotClient.progress( arguments.config.url(), arguments.config.site(), arguments.token, id, state.offset );
			} catch ( Deploybot exception ) {
				answer = {};
			}
			if ( ( answer.statusCode ?: 0 ) != 200 || !( answer.isJson ?: false ) || !isStruct( answer.json.data ?: "" ) ) {
				failures++;
				if ( failures >= variables.maxPollFailures ) {
					stop( "Lost track of the push: DeployBot did not answer #failures# progress requests in a row. The push may still be running on the server; see #where#.", "Deploybot.Timeout" );
				}
				continue;
			}
			failures = 0;
			data     = answer.json.data;
			report( data, state );
			if ( isBoolean( data.terminal ?: "" ) && data.terminal ) {
				break;
			}
		}
		// every result, even one whose log line never ended
		printResults( isArray( data.steps ?: "" ) ? data.steps : [], state, "" );
		var outcome = isStruct( data.outcome ?: "" ) ? data.outcome : {};
		return {
			ok            : isBoolean( outcome.ok ?: "" ) && outcome.ok,
			errorCode     : toString( outcome.error ?: "" ),
			steps         : isArray( data.steps ?: "" ) ? data.steps : [],
			rolledBack    : isBoolean( outcome.rolledBack ?: "" ) && outcome.rolledBack,
			healthyBefore : isBoolean( outcome.healthyBefore ?: "" ) ? outcome.healthyBefore : true,
			deployId      : id,
			recordUrl     : recordUrl
		};
	}

	/**
	 * Prints what one progress answer adds. The log's new whole lines give the step starts and
	 * the health attempts; the steps give each result, printed once and in order. A step's start
	 * waits until the step before it has a result, because the server writes the log a moment
	 * before it saves the steps.
	 *
	 * @data  The progress answer's data.
	 * @state { offset, shown } carried from one answer to the next.
	 */
	private void function report( required struct data, required struct state ){
		var steps = isArray( arguments.data.steps ?: "" ) ? arguments.data.steps : [];
		var text  = toString( arguments.data.log ?: "" );
		var pos   = 0;
		while ( true ) {
			var lineEnd = find( chr( 10 ), text, pos + 1 );
			// a line still being written is read again with the next answer
			if ( !lineEnd ) {
				break;
			}
			var line   = mid( text, pos + 1, lineEnd - pos - 1 );
			var header = reFind( "^=== step (\S+) \(([^)]*)\) ===$", line, 1, true );
			if ( header.pos[ 1 ] ) {
				var stepId = mid( line, header.pos[ 2 ], header.len[ 2 ] );
				if ( !stepIndex( steps, stepId ) && hasOpenStep( steps ) ) {
					break;
				}
				printResults( steps, arguments.state, stepId );
				announce( stepId, mid( line, header.pos[ 3 ], header.len[ 3 ] ) );
			} else {
				var attempt = reFind( "^\[[0-9:]+\]\s+\[[^\]]*\]\s+((attempt [0-9]+/[0-9]+:|retrying in ).*)$", line, 1, true );
				if ( attempt.pos[ 1 ] ) {
					say( "      " & mid( line, attempt.pos[ 2 ], attempt.len[ 2 ] ) );
				}
			}
			pos = lineEnd;
		}
		arguments.state.offset += pos;
		if ( pos == len( text ) ) {
			printResults( steps, arguments.state, "" );
		}
	}

	/**
	 * Prints the results not printed yet of the steps that have ended, up to the step stopId
	 * (all of them when stopId is empty or not in the list).
	 *
	 * @steps  The steps from the progress answer.
	 * @state  { offset, shown }.
	 * @stopId The step to stop before.
	 */
	private void function printResults( required array steps, required struct state, required string stopId ){
		for ( var i = 1; i <= arguments.steps.len(); i++ ) {
			var step = arguments.steps[ i ];
			if ( !isStruct( step ) ) {
				continue;
			}
			if ( len( arguments.stopId ) && ( step.id ?: "" ) == arguments.stopId ) {
				break;
			}
			if ( !arguments.state.shown.keyExists( i ) && !listFindNoCase( "running,queued", step.status ?: "" ) ) {
				printStep( step );
				arguments.state.shown[ i ] = true;
			}
		}
	}

	/**
	 * Prints a line when a step that can take a while starts.
	 *
	 * @stepId   The step id.
	 * @stepType The step type.
	 */
	private void function announce( required string stepId, required string stepType ){
		if ( arguments.stepId == "precheck" ) {
			say( "  Checking the site before writing the file..." );
		} else if ( arguments.stepType == "http.reinit" ) {
			say( "  Reloading the site..." );
		} else if ( arguments.stepType == "http.health" ) {
			say( "  Checking the site's health..." );
		} else if ( arguments.stepId == "rollback" ) {
			say( "  Putting the previous env file back..." );
		}
	}

	/**
	 * The position of the step with this id in the list, or 0.
	 */
	private numeric function stepIndex( required array steps, required string stepId ){
		for ( var i = 1; i <= arguments.steps.len(); i++ ) {
			if ( isStruct( arguments.steps[ i ] ) && ( arguments.steps[ i ].id ?: "" ) == arguments.stepId ) {
				return i;
			}
		}
		return 0;
	}

	/**
	 * True when a step in the list has not ended yet.
	 */
	private boolean function hasOpenStep( required array steps ){
		for ( var step in arguments.steps ) {
			if ( isStruct( step ) && listFindNoCase( "running,queued", step.status ?: "" ) ) {
				return true;
			}
		}
		return false;
	}

	/**
	 * A followed push's result as a client response, so interpret() decides it like any answer.
	 *
	 * @result What follow() returned.
	 */
	private struct function asResponse( required struct result ){
		var status = 200;
		if ( !arguments.result.ok ) {
			status = listFindNoCase( "site_down,health_failed,reinit_failed", arguments.result.errorCode ) ? 502 : 500;
		}
		return { statusCode : status, isJson : true, json : { data : arguments.result, messages : [] } };
	}

	/**
	 * Prints the result of a push that had no failed step. It claims a reinit and a health check
	 * only when those steps succeeded. A site without a reinit or health URL gets warnings
	 * instead, and the push still counts as done.
	 *
	 * @data The result struct from the server.
	 */
	private void function printOutcome( required struct data ){
		var reinitDone = stepStatus( arguments.data, "http.reinit" ) == "success";
		var healthDone = stepStatus( arguments.data, "http.health" ) == "success";
		if ( reinitDone && healthDone ) {
			good( "Pushed. The site was reinitialized and passed its health check." );
			return;
		}
		warn( "Pushed, with warnings. Check the steps above." );
		if ( !reinitDone ) {
			warn( "DeployBot did not reinitialize the site. The site may still use its old settings." );
		}
		if ( !healthDone ) {
			warn( "DeployBot did not check the site's health." );
		}
	}

	/**
	 * Turns a client response into the server's result struct (the envelope's data). It throws a
	 * Deploybot exception for every response that is not ok. When the response carries steps or
	 * missing keys, it prints them first.
	 *
	 * @response   The struct from DeploybotClient: { statusCode, isJson, json }.
	 * @stepsShown True when follow() has printed the steps already.
	 */
	struct function interpret( required struct response, boolean stepsShown = false ){
		var status = arguments.response.statusCode;
		var data   = arguments.response.json.keyExists( "data" ) && isStruct( arguments.response.json.data ) ? arguments.response.json.data : {};

		// DeployBot answers an address outside DEPLOYBOT_ADMIN_ALLOWLIST with its plain 404 page,
		// so a 404 is far more often the allowlist than a wrong URL.
		if ( status == 404 ) {
			fail(
				"DeployBot did not find the env API (HTTP 404).",
				[
					"If DEPLOYBOT_ADMIN_ALLOWLIST is set on the server, add this computer's public address to it.",
					"Check that deploybot.url in box.json points to the DeployBot server.",
					"The server may run a DeployBot version without the /api/v1 env push."
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

		var errorCode = data.errorCode ?: "";
		var said      = serverMessage( arguments.response.json );
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
		if ( errorCode == "site_down" ) {
			if ( !arguments.stepsShown ) printSteps( data );
			printRecord( data );
			stop(
				"The env file was pushed, but the site was already failing before the push, so DeployBot kept the new file instead of rolling it back. The site is still down: its DeployBot record says why.",
				"Deploybot.SiteDown"
			);
		}
		if ( status == 502 || errorCode == "health_failed" || errorCode == "reinit_failed" ) {
			if ( arguments.stepsShown ) {
				printRollback( data );
			} else {
				printSteps( data );
			}
			printRecord( data );
			var reason = errorCode == "reinit_failed" ? "the site did not reinitialize" : "the site failed its health check";
			stop(
				"The push failed: #reason#. " & ( ( data.rolledBack ?: false ) ? "DeployBot rolled the env file back." : "DeployBot did not report a rollback. Check the site now." ),
				"Deploybot.PushFailed"
			);
		}
		if ( errorCode == "write_failed" ) {
			if ( !arguments.stepsShown ) printSteps( data );
			printRecord( data );
			stop( "The push failed: DeployBot could not write the env file.", "Deploybot.PushFailed" );
		}
		if ( status == 500 ) {
			stop( "DeployBot hit an internal error (#len( errorCode ) ? errorCode : "HTTP 500"#). Nothing was written. Check DeployBot's log.", "Deploybot.ServerError" );
		}
		if ( len( errorCode ) ) {
			stop( "DeployBot reported an error: #errorCode# (HTTP #status#).#said#", "Deploybot.Http" );
		}
		stop( "DeployBot answered with an unexpected result (HTTP #status#).#said#", "Deploybot.Http" );
	}

	/**
	 * The server's first message, as " It says: <message>", or an empty string when it sent none.
	 *
	 * @json The parsed response envelope.
	 */
	private string function serverMessage( required struct json ){
		var messages = arguments.json.messages ?: [];
		if ( isArray( messages ) && messages.len() && isSimpleValue( messages[ 1 ] ) && len( messages[ 1 ] ) ) {
			return " It says: " & messages[ 1 ];
		}
		return "";
	}

	/**
	 * Runs the local check and stops on a file that git tracks or on missing keys unless force is
	 * true. With force, those and a missing .env.example become warnings.
	 *
	 * @config The loaded DeploybotConfig.
	 * @force  True to continue after a failed check.
	 */
	private void function localCheck( required any config, required boolean force ){
		var checker = service( "EnvChecker" );
		var result  = {};
		if ( checker.safety( arguments.config ).tracked ) {
			if ( !arguments.force ) {
				stop( "#arguments.config.envFile()# is tracked by git. Remove it from git and change its secrets, or use --force to push anyway.", "Deploybot.EnvTracked" );
			}
			warn( "Continuing with a file that git tracks because of --force." );
		}
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
	 * Returns the status of the step with this id, or an empty string when the result has none.
	 *
	 * @data The result struct from the server.
	 * @id   The step id, such as http.reinit.
	 */
	private string function stepStatus( required struct data, required string id ){
		var steps = arguments.data.steps ?: [];
		if ( isArray( steps ) ) {
			for ( var step in steps ) {
				if ( isStruct( step ) && ( step.id ?: "" ) == arguments.id ) {
					return step.status ?: "";
				}
			}
		}
		return "";
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
				if ( isStruct( step ) ) {
					printStep( step );
				}
			}
		}
		printRollback( arguments.data );
	}

	/**
	 * Prints one step as "[status] id - summary", colored by its status.
	 *
	 * @step A step struct from the server.
	 */
	private void function printStep( required struct step ){
		var line = "  [#arguments.step.status ?: "?"#] #arguments.step.id ?: "?"# - #arguments.step.summary ?: ""#";
		switch ( arguments.step.status ?: "" ) {
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

	/**
	 * Prints whether the server rolled the env file back, when the result says.
	 *
	 * @data The result struct from the server.
	 */
	private void function printRollback( required struct data ){
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
