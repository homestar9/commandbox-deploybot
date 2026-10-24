/**
 * Talks to the DeployBot server over HTTP. This is the only component that uses the network, so
 * specs stub it.
 *
 * The server contract:
 *
 *   POST {url}/api/v1/sites/{slug}/env?dryRun=true|false&force=true|false[&async=true]
 *   Authorization: Bearer <envToken>
 *   Content-Type: text/plain; charset=utf-8
 *   Body: the raw .env text, at most 64 KB.
 *
 * With async=true a server that supports it answers 202 as soon as the push is recorded, and
 * the push runs on the server. Follow it with:
 *
 *   GET {url}/api/v1/sites/{slug}/env/{deployId}?offset=N
 *   Authorization: Bearer <envToken>
 *
 * An older server ignores async and answers when the push has finished, as before.
 *
 * The response is DeployBot's API envelope, { data, error, messages }. See EnvPusher for the
 * fields and the status codes.
 *
 * This component does not decide what a status code means. It returns the status code and the
 * parsed JSON. It throws a Deploybot exception only when no usable HTTP response arrived:
 * Deploybot.Timeout, Deploybot.Tls, Deploybot.Connection, or Deploybot.Redirect.
 *
 * Nothing in this component prints or logs the token or the body. Error messages never include
 * either one.
 */
component singleton {

	/** The number of seconds to wait. The server reinitializes and health-checks the site. */
	variables.timeoutSeconds = 120;
	/** The number of seconds to wait for one progress answer. The server only reads a file. */
	variables.progressTimeoutSeconds = 15;

	/**
	 * Sends an env file to the server and returns { statusCode, isJson, json }.
	 * When the body is not JSON, isJson is false and json is an empty struct.
	 *
	 * @url    The DeployBot URL without a final slash.
	 * @site   The site slug.
	 * @token  The env token. It goes only in the Authorization header.
	 * @body   The env file as binary data. It is sent unchanged.
	 * @dryRun True to ask the server for a diff only.
	 * @force  True to push even if the server reports missing keys.
	 * @async  True to ask the server to answer at once (202) and run the push in the background.
	 */
	struct function pushEnv(
		required string url,
		required string site,
		required string token,
		required any body,
		boolean dryRun = false,
		boolean force  = false,
		boolean async  = false
	){
		var endpoint = arguments.url & "/api/v1/sites/" & encodeForURL( arguments.site ) & "/env"
			& "?dryRun=" & ( arguments.dryRun ? "true" : "false" )
			& "&force=" & ( arguments.force ? "true" : "false" )
			& ( arguments.async ? "&async=true" : "" );
		return send( "POST", endpoint, arguments.token, arguments.url, variables.timeoutSeconds, arguments.body );
	}

	/**
	 * Asks how an async push is getting on and returns { statusCode, isJson, json }. data holds
	 * the push's steps, its log text from offset, the next offset, terminal, and outcome.
	 *
	 * @url      The DeployBot URL without a final slash.
	 * @site     The site slug.
	 * @token    The env token. It goes only in the Authorization header.
	 * @deployId The id the push's 202 answer carried.
	 * @offset   Where to start reading the push's log, from the previous answer.
	 */
	struct function progress(
		required string url,
		required string site,
		required string token,
		required string deployId,
		numeric offset = 0
	){
		var endpoint = arguments.url & "/api/v1/sites/" & encodeForURL( arguments.site ) & "/env/"
			& encodeForURL( arguments.deployId ) & "?offset=" & int( arguments.offset );
		return send( "GET", endpoint, arguments.token, arguments.url, variables.progressTimeoutSeconds );
	}

	/**
	 * Sends one request and returns { statusCode, isJson, json }, or throws a Deploybot exception
	 * when no usable HTTP response arrived.
	 *
	 * @method   POST or GET.
	 * @endpoint The full address.
	 * @token    The env token.
	 * @baseUrl  The DeployBot URL, for messages.
	 * @timeout  Seconds to wait.
	 * @body     The request body (POST only).
	 */
	private struct function send(
		required string method,
		required string endpoint,
		required string token,
		required string baseUrl,
		required numeric timeout,
		any body
	){
		var bearer      = "Bearer " & arguments.token;
		var hasBody     = !isNull( arguments.body );
		var requestBody = hasBody ? arguments.body : "";
		var httpResult  = "";

		try {
			cfhttp(
				url          = arguments.endpoint,
				method       = arguments.method,
				timeout      = arguments.timeout,
				throwonerror = false,
				redirect     = false,
				result       = "local.httpResult"
			) {
				cfhttpparam( type = "header", name = "Authorization", value = bearer );
				cfhttpparam( type = "header", name = "Accept", value = "application/json" );
				if ( hasBody ) {
					cfhttpparam( type = "header", name = "Content-Type", value = "text/plain; charset=utf-8" );
					cfhttpparam( type = "body", value = requestBody );
				}
			}
		} catch ( any exception ) {
			classifyFailure( exception.message & " " & ( exception.detail ?: "" ), arguments.baseUrl, arguments.timeout );
		}

		var statusCode = val( listFirst( httpResult.statuscode ?: "0", " " ) );
		if ( statusCode == 0 || statusCode == 408 ) {
			classifyFailure( ( httpResult.errordetail ?: "" ) & " " & ( httpResult.statuscode ?: "" ), arguments.baseUrl, arguments.timeout );
		}
		if ( statusCode >= 300 && statusCode < 400 ) {
			throw(
				type    = "Deploybot.Redirect",
				message = "DeployBot redirected the request (HTTP #statusCode#). The token was not sent to the new address. Check deploybot.url in box.json: it must be the exact https address of the server."
			);
		}

		return parseBody( statusCode, httpResult.fileContent ?: "" );
	}

	/**
	 * Throws the right Deploybot exception for a failed request.
	 *
	 * @text    A description of the failure from the HTTP engine. It is only searched, never shown.
	 * @url     The DeployBot URL for the message.
	 * @timeout The seconds the request waited.
	 */
	private void function classifyFailure( required string text, required string url, numeric timeout = variables.timeoutSeconds ){
		var haystack = lCase( arguments.text );
		if ( reFind( "timed out|timeout|time-out", haystack ) ) {
			throw(
				type    = "Deploybot.Timeout",
				message = "DeployBot did not answer within #arguments.timeout# seconds. The push may still be running on the server. Check the DeployBot deploy log before you try again."
			);
		}
		if ( reFind( "ssl|tls|certificate|pkix|handshake|trust", haystack ) ) {
			throw(
				type    = "Deploybot.Tls",
				message = "The TLS connection to #arguments.url# failed. The certificate may be expired, self-signed, or issued for another host name. Check deploybot.url in box.json and the server's certificate."
			);
		}
		throw(
			type    = "Deploybot.Connection",
			message = "Could not reach DeployBot at #arguments.url#. Check deploybot.url in box.json, your network, and that the server is running."
		);
	}

	/**
	 * Parses the response body as JSON when possible.
	 *
	 * @statusCode The HTTP status code.
	 * @content    The response body, as text or bytes.
	 */
	private struct function parseBody( required numeric statusCode, required any content ){
		var text = isBinary( arguments.content ) ? charsetEncode( arguments.content, "utf-8" ) : toString( arguments.content );
		var parsed = "";
		if ( len( trim( text ) ) && isJSON( text ) ) {
			parsed = deserializeJSON( text );
		}
		if ( isStruct( parsed ) ) {
			return { statusCode : arguments.statusCode, isJson : true, json : parsed };
		}
		return { statusCode : arguments.statusCode, isJson : false, json : {} };
	}
}
