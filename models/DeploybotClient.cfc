/**
 * Talks to the DeployBot server over HTTP. This is the only component that uses the network, so
 * specs stub it.
 *
 * The server contract:
 *
 *   POST {url}/api/v1/sites/{slug}/env?dryRun=true|false&force=true|false
 *   Authorization: Bearer <envToken>
 *   Content-Type: text/plain; charset=utf-8
 *   Body: the raw .env text, at most 64 KB.
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
	 */
	struct function pushEnv(
		required string url,
		required string site,
		required string token,
		required any body,
		boolean dryRun = false,
		boolean force  = false
	){
		var endpoint = arguments.url & "/api/v1/sites/" & encodeForURL( arguments.site ) & "/env"
			& "?dryRun=" & ( arguments.dryRun ? "true" : "false" )
			& "&force=" & ( arguments.force ? "true" : "false" );
		var bearer   = "Bearer " & arguments.token;
		var requestBody = arguments.body;
		var httpResult  = "";

		try {
			cfhttp(
				url          = endpoint,
				method       = "POST",
				timeout      = variables.timeoutSeconds,
				throwonerror = false,
				redirect     = false,
				result       = "local.httpResult"
			) {
				cfhttpparam( type = "header", name = "Authorization", value = bearer );
				cfhttpparam( type = "header", name = "Accept", value = "application/json" );
				cfhttpparam( type = "header", name = "Content-Type", value = "text/plain; charset=utf-8" );
				cfhttpparam( type = "body", value = requestBody );
			}
		} catch ( any exception ) {
			classifyFailure( exception.message & " " & ( exception.detail ?: "" ), arguments.url );
		}

		var statusCode = val( listFirst( httpResult.statuscode ?: "0", " " ) );
		if ( statusCode == 0 || statusCode == 408 ) {
			classifyFailure( ( httpResult.errordetail ?: "" ) & " " & ( httpResult.statuscode ?: "" ), arguments.url );
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
	 * @text A description of the failure from the HTTP engine. It is only searched, never shown.
	 * @url  The DeployBot URL for the message.
	 */
	private void function classifyFailure( required string text, required string url ){
		var haystack = lCase( arguments.text );
		if ( reFind( "timed out|timeout|time-out", haystack ) ) {
			throw(
				type    = "Deploybot.Timeout",
				message = "DeployBot did not answer within #variables.timeoutSeconds# seconds. The push may still be running on the server. Check the DeployBot deploy log before you try again."
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
