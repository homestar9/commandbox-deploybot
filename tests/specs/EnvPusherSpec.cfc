/** Checks the push flow with a fake DeployBot client: decisions, output, and error mapping. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "EnvPusher", function(){
			beforeEach( function(){
				root  = createTempProject();
				lines = [];
				fakeClient = createFakeClient();
				stubGit();
				writeBoxJson( root );
				writeText( root & "/.env.example", "APP_NAME=" & chr( 10 ) & "API_KEY=" );
				writeText( root & "/.env.production", "APP_NAME=#secretValue#" & chr( 10 ) & "API_KEY=#secretValue#" );
				pusher = createPusher( fakeClient, lines );
				asked  = [];
				confirmYes = function( question ){
					asked.append( question );
					return true;
				};
				confirmNo = function( question ){
					asked.append( question );
					return false;
				};
			} );

			afterEach( function(){
				deleteDirectory( root );
			} );

			describe( "decisions", function(){
				it( "prints the dry-run diff of key names and stops with --dryRun", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ], [ "OLD_KEY" ], [ "API_KEY" ], [ "SERVER_MISSING" ], [ "SERVER_EXTRA" ] ) );
					pusher.run( config = loadConfig( root ), dryRun = true );

					expect( fakeClient.calls().len() ).toBe( 1 );
					expect( fakeClient.calls()[ 1 ].dryRun ).toBeTrue();
					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( "+ NEW_KEY" );
					expect( output ).toInclude( "- OLD_KEY" );
					expect( output ).toInclude( "~ API_KEY" );
					expect( output ).toInclude( "Server reports missing keys: SERVER_MISSING" );
					expect( output ).toInclude( "Server reports extra keys: SERVER_EXTRA" );
					expect( output ).toInclude( "Dry run only" );
				} );

				it( "stops without asking when nothing changed", function(){
					fakeClient.respond( diffResponse() );
					pusher.run( config = loadConfig( root ), confirm = confirmYes );

					expect( fakeClient.calls().len() ).toBe( 1 );
					expect( asked.len() ).toBe( 0 );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "No changes" );
				} );

				it( "asks before the real push and sends it after a yes", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ], [], [ "API_KEY" ] ) );
					fakeClient.respond( pushResponse() );
					pusher.run( config = loadConfig( root ), confirm = confirmYes );

					expect( asked.len() ).toBe( 1 );
					expect( asked[ 1 ] ).toInclude( "2 key changes" );
					expect( asked[ 1 ] ).toInclude( "my-site" );
					expect( fakeClient.calls().len() ).toBe( 2 );
					expect( fakeClient.calls()[ 1 ].dryRun ).toBeTrue();
					expect( fakeClient.calls()[ 2 ].dryRun ).toBeFalse();
				} );

				it( "does not push after a no, and stops with an error so scripts stop too", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					expect( function(){
						pusher.run( config = loadConfig( root ), confirm = confirmNo );
					} ).toThrow( type = "Deploybot.Cancelled", regex = "Nothing was changed" );

					expect( asked.len() ).toBe( 1 );
					expect( fakeClient.calls().len() ).toBe( 1 );
				} );

				it( "stops when the input ends before an answer", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					expect( function(){
						pusher.run( config = loadConfig( root ), confirm = function( question ){
							throw( type = "EndOfFileException", message = "EOF" );
						} );
					} ).toThrow( type = "Deploybot.NoAnswer", regex = "cannot answer.*--yes" );
					expect( fakeClient.calls().len() ).toBe( 1 );
				} );

				it( "skips the question with --yes", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( pushResponse() );
					pusher.run( config = loadConfig( root ), yes = true, confirm = confirmNo );

					expect( asked.len() ).toBe( 0 );
					expect( fakeClient.calls().len() ).toBe( 2 );
				} );

				it( "does not push without --yes when no one can answer", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					expect( function(){
						pusher.run( config = loadConfig( root ) );
					} ).toThrow( type = "Deploybot.NoAnswer", regex = "cannot answer.*--yes" );
					expect( fakeClient.calls().len() ).toBe( 1 );
				} );

				it( "finishes without an error when nothing changed and no one can answer (release hook)", function(){
					fakeClient.respond( diffResponse() );
					pusher.run( config = loadConfig( root ) );

					expect( fakeClient.calls().len() ).toBe( 1 );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "No changes" );
				} );

				it( "stops on missing local keys before any request", function(){
					writeText( root & "/.env.production", "APP_NAME=1" );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.MissingKeys", regex = "1 key" );
					expect( fakeClient.calls().len() ).toBe( 0 );
				} );

				it( "continues past missing local keys with --force and sends force=true", function(){
					writeText( root & "/.env.production", "APP_NAME=1" );
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( pushResponse() );
					pusher.run( config = loadConfig( root ), yes = true, force = true );

					expect( fakeClient.calls().len() ).toBe( 2 );
					expect( fakeClient.calls()[ 1 ].force ).toBeTrue();
					expect( fakeClient.calls()[ 2 ].force ).toBeTrue();
					expect( lines.toList( chr( 10 ) ) ).toInclude( "because of --force" );
				} );

				it( "stops before any request when git tracks the env file", function(){
					stubGit( { tracked : true } );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.EnvTracked", regex = "--force" );
					expect( fakeClient.calls().len() ).toBe( 0 );
				} );

				it( "pushes a file that git tracks only with --force, and warns", function(){
					stubGit( { tracked : true } );
					fakeClient.respond( diffResponse() );
					pusher.run( config = loadConfig( root ), force = true );
					expect( fakeClient.calls().len() ).toBe( 1 );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "a file that git tracks because of --force" );
				} );

				it( "sends force=false without --force", function(){
					fakeClient.respond( diffResponse() );
					pusher.run( config = loadConfig( root ) );
					expect( fakeClient.calls()[ 1 ].force ).toBeFalse();
				} );

				it( "skips a missing .env.example only with --force", function(){
					fileDelete( root & "/.env.example" );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.NoExample" );

					fakeClient.respond( diffResponse() );
					pusher.run( config = loadConfig( root ), force = true );
					expect( fakeClient.calls().len() ).toBe( 1 );
				} );

				it( "stops when no token is saved", function(){
					pusher = createPusher( fakeClient, lines, false );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.NoToken", regex = "my-site" );
					expect( fakeClient.calls().len() ).toBe( 0 );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "box deploybot token set" );
				} );

				it( "sends the file bytes unchanged, the saved token, and the site", function(){
					var bom = charsetDecode( chr( 65279 ) & "APP_NAME=1" & chr( 13 ) & chr( 10 ) & "API_KEY=2" & chr( 13 ) & chr( 10 ), "utf-8" );
					fileWrite( root & "/.env.production", bom );
					fakeClient.respond( diffResponse() );
					pusher.run( config = loadConfig( root ) );

					var call = fakeClient.calls()[ 1 ];
					expect( call.bytes ).toBe( arrayLen( bom ) );
					expect( call.token ).toBe( secretToken );
					expect( call.site ).toBe( "my-site" );
					expect( call.url ).toBe( "https://deploybot.example.com" );
				} );

				it( "refuses a file over 64 KB before any request", function(){
					fileWrite( root & "/.env.production", repeatString( "a", 65537 ) );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.TooLarge" );
					expect( fakeClient.calls().len() ).toBe( 0 );
				} );
			} );

			describe( "push output", function(){
				it( "prints each step, the rollback state, and the record URL", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( pushResponse( [
						{ id : "write", status : "success", summary : "Wrote the file" },
						{ id : "acl", status : "warning", summary : "ACL skipped" },
						{ id : "http.reinit", status : "success", summary : "Reinit OK" },
						{ id : "http.health", status : "success", summary : "Health OK" }
					] ) );
					pusher.run( config = loadConfig( root ), yes = true );

					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( "[success] write - Wrote the file" );
					expect( output ).toInclude( "[warning] acl - ACL skipped" );
					expect( output ).toInclude( "[success] http.health - Health OK" );
					expect( output ).toInclude( "Rolled back: no" );
					expect( output ).toInclude( "reinitialized and passed its health check" );
					expect( output ).toInclude( "Record: https://deploybot.example.com/deploys/d1" );
				} );

				it( "does not claim a reinit or a health check that only warned", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( pushResponse( [
						{ id : "write", status : "success", summary : "Wrote the file" },
						{ id : "http.reinit", status : "warning", summary : "no reinit url configured" },
						{ id : "http.health", status : "warning", summary : "no health url configured" }
					] ) );
					pusher.run( config = loadConfig( root ), yes = true );

					var output = lines.toList( chr( 10 ) );
					expect( output ).notToInclude( "passed its health check" );
					expect( output ).toInclude( "Pushed, with warnings" );
					expect( output ).toInclude( "did not reinitialize the site" );
					expect( output ).toInclude( "did not check the site's health" );
				} );

				it( "warns when the result has no reinit or health step", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( pushResponse() );
					pusher.run( config = loadConfig( root ), yes = true );

					var output = lines.toList( chr( 10 ) );
					expect( output ).notToInclude( "passed its health check" );
					expect( output ).toInclude( "did not reinitialize the site" );
				} );

				it( "fails when the server says ok but a step failed", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( pushResponse( [ { id : "acl", status : "failed", summary : "ACL failed" } ] ) );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.PushFailed" );
					expect( lines.toList( chr( 10 ) ) ).toInclude( "[failed] acl - ACL failed" );
				} );

				it( "prints steps and the rollback when the health check fails", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( jsonResponse( 502, {
						ok         : false,
						errorCode  : "health_failed",
						steps      : [
							{ id : "write", status : "success", summary : "Wrote the file" },
							{ id : "http.health", status : "failed", summary : "HTTP 500" },
							{ id : "rollback", status : "success", summary : "Restored backup" }
						],
						rolledBack : true,
						recordUrl  : "https://deploybot.example.com/deploys/d2"
					} ) );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.PushFailed", regex = "health check.*rolled the env file back" );

					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( "[failed] http.health - HTTP 500" );
					expect( output ).toInclude( "[success] rollback - Restored backup" );
					expect( output ).toInclude( "Rolled back: the previous env file is back in place." );
					expect( output ).toInclude( "Record: https://deploybot.example.com/deploys/d2" );
				} );
			} );

			describe( "following an async push", function(){
				beforeEach( function(){
					pusher.setPollMs( 0 );
					accepted = jsonResponse( 202, { ok : true, errorCode : "", queued : true, deployId : "d9", recordUrl : "https://deploybot.example.com/deploys/d9" } );
				} );

				it( "asks for async and prints each step, the health attempts and retries live, in order", function(){
					var first = chr( 10 ) & "=== step precheck (http.health) ===" & chr( 10 )
						& "[12:00:00] [precheck] GET https://x/health, expect 200, up to 1 attempt(s)" & chr( 10 )
						& "[12:00:00] [precheck] attempt 1/1: HTTP 200 in 5ms" & chr( 10 );
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( accepted );
					fakeClient.respond( progressResponse( [ step( "precheck", "running" ) ], first ) );
					fakeClient.respond( progressResponse(
						[ step( "precheck", "success", "HTTP 200" ), step( "write", "success", "wrote 2 key(s)" ), step( "acl", "success", "locked down" ), step( "http.reinit", "success", "HTTP 200" ), step( "http.health", "running" ) ],
						chr( 10 ) & "=== step write (env.write) ===" & chr( 10 ) & "[12:00:01] [write] wrote 2 key(s)" & chr( 10 )
						& chr( 10 ) & "=== step acl (env.acl) ===" & chr( 10 ) & "[12:00:01] [acl] icacls" & chr( 10 )
						& chr( 10 ) & "=== step http.reinit (http.reinit) ===" & chr( 10 ) & "[12:00:02] [http.reinit] HTTP 200 in 9ms" & chr( 10 )
						& chr( 10 ) & "=== step http.health (http.health) ===" & chr( 10 )
						& "[12:00:02] [http.health] attempt 1/3: HTTP 500 in 18ms" & chr( 10 )
						& "[12:00:02] [http.health] retrying in 3s" & chr( 10 )
					) );
					fakeClient.respond( progressResponse(
						[ step( "precheck", "success", "HTTP 200" ), step( "write", "success", "wrote 2 key(s)" ), step( "acl", "success", "locked down" ), step( "http.reinit", "success", "HTTP 200" ), step( "http.health", "success", "HTTP 200 after 2 attempt(s)" ) ],
						"[12:00:05] [http.health] attempt 2/3: HTTP 200 in 240ms" & chr( 10 ) & "[12:00:05] environment file push success (4.0s)" & chr( 10 ),
						{ ok : true, error : "", rolledBack : false, healthyBefore : true }
					) );
					pusher.run( config = loadConfig( root ), yes = true );

					expect( fakeClient.calls()[ 2 ].async ).toBeTrue();
					expect( fakeClient.calls()[ 3 ].call ).toBe( "progress" );
					expect( fakeClient.calls()[ 3 ].deployId ).toBe( "d9" );
					expect( fakeClient.calls()[ 3 ].offset ).toBe( 0 );
					expect( fakeClient.calls()[ 4 ].offset ).toBe( len( first ), "the next answer starts where the last one ended" );
					var output = lines.toList( chr( 10 ) );
					expect( inOrder( output, [
						"Checking the site before writing the file...",
						"attempt 1/1: HTTP 200 in 5ms",
						"[success] precheck - HTTP 200",
						"[success] write - wrote 2 key(s)",
						"[success] acl - locked down",
						"Reloading the site...",
						"[success] http.reinit - HTTP 200",
						"Checking the site's health...",
						"attempt 1/3: HTTP 500 in 18ms",
						"retrying in 3s",
						"attempt 2/3: HTTP 200 in 240ms",
						"[success] http.health - HTTP 200 after 2 attempt(s)",
						"Rolled back: no",
						"reinitialized and passed its health check",
						"Record: https://deploybot.example.com/deploys/d9"
					] ) ).toBe( "" );
					expect( output ).notToInclude( "GET https://x/health", "only attempts and retries are forwarded" );
				} );

				it( "waits for a step's result before announcing the next step", function(){
					var held = chr( 10 ) & "=== step http.reinit (http.reinit) ===" & chr( 10 );
					var done = chr( 10 ) & "=== step write (env.write) ===" & chr( 10 ) & "[12:00:01] [write] wrote" & chr( 10 );
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( accepted );
					// the log already has the reinit's start, the steps still show write running
					fakeClient.respond( progressResponse( [ step( "write", "running" ) ], done & held ) );
					fakeClient.respond( progressResponse(
						[ step( "write", "success", "wrote" ), step( "http.reinit", "success", "HTTP 200" ), step( "http.health", "success", "HTTP 200" ) ],
						mid( held, 2, len( held ) - 1 ),
						{ ok : true, error : "", rolledBack : false, healthyBefore : true }
					) );
					pusher.run( config = loadConfig( root ), yes = true );

					// past the blank line, up to the header: the header line is read again
					expect( fakeClient.calls()[ 4 ].offset ).toBe( len( done ) + 1 );
					expect( inOrder( lines.toList( chr( 10 ) ), [ "[success] write - wrote", "Reloading the site...", "[success] http.reinit - HTTP 200" ] ) ).toBe( "" );
				} );

				it( "says the site was already down when the server kept the file, printing each step once", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( accepted );
					fakeClient.respond( progressResponse(
						[ step( "precheck", "failed", "HTTP 500" ), step( "write", "success", "wrote" ), step( "http.reinit", "failed", "HTTP 500" ), step( "http.health", "failed", "HTTP 500" ) ],
						"",
						{ ok : false, error : "site_down", rolledBack : false, healthyBefore : false }
					) );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.SiteDown", regex = "already failing before the push" );
					var output = lines.toList( chr( 10 ) );
					expect( ( output.len() - output.replace( "[success] write - wrote", "", "all" ).len() ) / len( "[success] write - wrote" ) ).toBe( 1, "printed once" );
					expect( output ).toInclude( "Record: https://deploybot.example.com/deploys/d9" );
				} );

				it( "reports a failed health check and the rollback after following it", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( accepted );
					fakeClient.respond( progressResponse(
						[ step( "write", "success", "wrote" ), step( "http.health", "failed", "HTTP 500" ), step( "rollback", "success", "previous file restored" ) ],
						"",
						{ ok : false, error : "health_failed", rolledBack : true, healthyBefore : true }
					) );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.PushFailed", regex = "health check.*rolled the env file back" );
					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( "[success] rollback - previous file restored" );
					expect( output ).toInclude( "Rolled back: the previous env file is back in place." );
				} );

				it( "gives up after five progress requests in a row fail, pointing at the record", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( accepted );
					for ( var i = 1; i <= 5; i++ ) {
						fakeClient.respond( "Deploybot.Timeout" );
					}
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.Timeout", regex = "Lost track of the push.*deploys/d9" );
				} );
			} );

			describe( "error mapping", function(){
				var cases = [
					{ status : 401, json : { ok : false, errorCode : "unauthorized" }, type : "Deploybot.Unauthorized", regex : "token is wrong, or the site slug" },
					{ status : 409, json : { ok : false, errorCode : "locked" }, type : "Deploybot.Locked", regex : "deploy is running" },
					{ status : 413, json : { ok : false, errorCode : "too_large" }, type : "Deploybot.TooLarge", regex : "too large" },
					{ status : 400, json : { ok : false, errorCode : "invalid_body" }, type : "Deploybot.InvalidBody", regex : "invalid_body" },
					{ status : 422, json : { ok : false, errorCode : "missing_keys", missing : [ "A_KEY", "B_KEY" ] }, type : "Deploybot.MissingKeys", regex : "2 missing keys" },
					{ status : 429, json : { ok : false }, type : "Deploybot.RateLimited", regex : "rate limiting" },
					{ status : 502, json : { ok : false, errorCode : "reinit_failed", rolledBack : true }, type : "Deploybot.PushFailed", regex : "did not reinitialize" },
					{ status : 502, json : { ok : false, errorCode : "health_failed", rolledBack : false }, type : "Deploybot.PushFailed", regex : "did not report a rollback" },
					{ status : 500, json : { ok : false, errorCode : "write_failed" }, type : "Deploybot.PushFailed", regex : "could not write" },
					{ status : 500, json : { ok : false, errorCode : "internal" }, type : "Deploybot.ServerError", regex : "internal error" },
					{ status : 403, json : { ok : false, errorCode : "https_required" }, type : "Deploybot.HttpsRequired", regex : "HTTPS" },
					{ status : 404, json : {}, type : "Deploybot.NotFound", regex : "did not find" },
					{ status : 503, json : { ok : false, errorCode : "weird" }, type : "Deploybot.Http", regex : "weird" },
					{ status : 418, json : { ok : false }, type : "Deploybot.Http", regex : "HTTP 418" },
					{ status : 405, json : { errorCode : "method" }, type : "Deploybot.Http", regex : "method \(HTTP 405\)" }
				];
				for ( var errorCase in cases ) {
					( function( errorCase ){
						var label = "maps HTTP " & errorCase.status & " " & ( errorCase.json.errorCode ?: "" ) & " to " & errorCase.type;
						it( label, function(){
							fakeClient.respond( jsonResponse( errorCase.status, errorCase.json ) );
							expect( function(){
								pusher.run( config = loadConfig( root ), dryRun = true );
							} ).toThrow( type = errorCase.type, regex = errorCase.regex );
						} );
					} )( errorCase );
				}

				it( "passes the server's own words on for an error it has no advice for", function(){
					fakeClient.respond( jsonResponse( 405, { errorCode : "method" }, [ "GET is not allowed here." ] ) );
					expect( function(){
						pusher.run( config = loadConfig( root ) );
					} ).toThrow( type = "Deploybot.Http", regex = "It says: GET is not allowed here\." );
				} );

				it( "names the missing keys and suggests --force on a 422", function(){
					fakeClient.respond( jsonResponse( 422, { ok : false, errorCode : "missing_keys", missing : [ "A_KEY", "B_KEY" ] } ) );
					try {
						pusher.run( config = loadConfig( root ) );
					} catch ( any exception ) {
						// The output below is what matters.
					}
					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( "  - A_KEY" );
					expect( output ).toInclude( "  - B_KEY" );
					expect( output ).toInclude( "--force" );
				} );

				it( "tells the user to check the slug and run token set on a 401", function(){
					fakeClient.respond( jsonResponse( 401, { ok : false, errorCode : "unauthorized" } ) );
					try {
						pusher.run( config = loadConfig( root ) );
					} catch ( any exception ) {
						// The output below is what matters.
					}
					var output = lines.toList( chr( 10 ) );
					expect( output ).toInclude( "deploybot.site" );
					expect( output ).toInclude( "box deploybot token set" );
				} );

				it( "reports a response that is not JSON", function(){
					fakeClient.respond( { statusCode : 200, isJson : false, json : {} } );
					expect( function(){
						pusher.run( config = loadConfig( root ) );
					} ).toThrow( type = "Deploybot.BadResponse", regex = "HTTP 200" );
				} );

				it( "reports a 200 response that is not ok", function(){
					fakeClient.respond( jsonResponse( 200, { ok : false } ) );
					expect( function(){
						pusher.run( config = loadConfig( root ) );
					} ).toThrow( type = "Deploybot.Http", regex = "unexpected" );
				} );

				it( "passes client failures through", function(){
					for ( var type in [ "Deploybot.Timeout", "Deploybot.Tls", "Deploybot.Connection", "Deploybot.Redirect" ] ) {
						fakeClient.respond( type );
						expect( function(){
							pusher.run( config = loadConfig( root ) );
						} ).toThrow( type = type );
					}
				} );

				it( "stops on an error from the real push after a good dry run", function(){
					fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
					fakeClient.respond( jsonResponse( 409, { ok : false, errorCode : "locked" } ) );
					expect( function(){
						pusher.run( config = loadConfig( root ), yes = true );
					} ).toThrow( type = "Deploybot.Locked" );
					expect( fakeClient.calls().len() ).toBe( 2 );
				} );
			} );

			describe( "secrets", function(){
				it( "never prints a file value or the token, in output or error messages", function(){
					var everything = [];
					var scenarios = [
						function(){
							fakeClient.respond( diffResponse( [ "NEW_KEY" ], [], [ "API_KEY" ] ) );
							fakeClient.respond( pushResponse( [ { id : "write", status : "success", summary : "ok" } ] ) );
							pusher.run( config = loadConfig( root ), yes = true );
						},
						function(){
							fakeClient.respond( jsonResponse( 401, { ok : false, errorCode : "unauthorized" } ) );
							pusher.run( config = loadConfig( root ), yes = true );
						},
						function(){
							fakeClient.respond( jsonResponse( 422, { ok : false, errorCode : "missing_keys", missing : [ "A_KEY" ] } ) );
							pusher.run( config = loadConfig( root ), yes = true );
						},
						function(){
							fakeClient.respond( "Deploybot.Timeout" );
							pusher.run( config = loadConfig( root ), yes = true );
						},
						function(){
							fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
							pusher.run( config = loadConfig( root ), confirm = confirmNo );
						},
						function(){
							fakeClient.respond( diffResponse( [ "NEW_KEY" ] ) );
							pusher.run( config = loadConfig( root ) );
						},
						function(){
							writeText( root & "/.env.production", "APP_NAME=#secretValue#" );
							pusher.run( config = loadConfig( root ), yes = true );
						}
					];
					for ( var scenario in scenarios ) {
						try {
							scenario();
						} catch ( any exception ) {
							everything.append( exception.message & " " & ( exception.detail ?: "" ) );
						}
					}
					var output = lines.toList( chr( 10 ) ) & chr( 10 ) & everything.toList( chr( 10 ) );
					expect( len( output ) ).toBeGT( 0 );
					expect( output ).notToInclude( secretValue );
					expect( output ).notToInclude( secretToken );
				} );
			} );
		} );
	}

	/** Builds a dry-run response with the given key names. */
	private struct function diffResponse(
		array added   = [],
		array removed = [],
		array changed = [],
		array missing = [],
		array extra   = []
	){
		var response = okResponse( { added : arguments.added, removed : arguments.removed, changed : arguments.changed } );
		response.json.data.dryRun  = true;
		response.json.data.missing = arguments.missing;
		response.json.data.extra   = arguments.extra;
		return response;
	}

	/** Builds a progress answer: steps, the log since the asked offset, and the outcome once it has ended. */
	private struct function progressResponse( required array steps, string log = "", struct outcome = {} ){
		var ended = !structIsEmpty( arguments.outcome );
		return jsonResponse( 200, {
			found    : true,
			id       : "d9",
			status   : ended ? ( arguments.outcome.ok ? "success" : "failed" ) : "running",
			terminal : ended,
			steps    : arguments.steps,
			log      : arguments.log,
			outcome  : arguments.outcome
		} );
	}

	/** A step as a progress answer lists it. */
	private struct function step( required string id, required string status, string summary = "" ){
		return { id : arguments.id, type : "", status : arguments.status, summary : arguments.summary };
	}

	/** "" when every needle appears in the text in this order, else the first one out of place. */
	private string function inOrder( required string text, required array needles ){
		var at = 0;
		for ( var needle in arguments.needles ) {
			var found = find( needle, arguments.text, at + 1 );
			if ( !found ) {
				return needle;
			}
			at = found;
		}
		return "";
	}

	/** Builds a successful real push response with the given steps. */
	private struct function pushResponse( array steps = [ { id : "write", status : "success", summary : "Wrote the file" } ] ){
		return okResponse( {}, arguments.steps );
	}
}
