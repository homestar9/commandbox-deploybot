/**
 * Reads .env text and finds key names and blank values.
 *
 * The key rule matches DeployBot's own env check: a line is `KEY=` or `export KEY=`. Lines that
 * start with # are comments. A byte order mark at the start of the text and CRLF line endings
 * are accepted.
 *
 * This component returns key names only. No function returns a value, so a caller cannot print
 * one by mistake.
 */
component singleton {

	/** The key rule shared with DeployBot's EnvCheck. */
	variables.keyPattern = "^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=";

	/** The largest body DeployBot accepts, in bytes. */
	variables.maxBytes = 65536;

	/** Returns the largest body DeployBot accepts, in bytes. */
	numeric function maxBytes(){
		return variables.maxBytes;
	}

	/**
	 * Reads a file as raw bytes. The bytes are sent to the server unchanged, so a byte order
	 * mark and line endings stay as the developer saved them. Throws Deploybot.EnvFile when the
	 * file is missing or too large.
	 *
	 * @path The full path to the env file.
	 */
	any function readBytes( required string path ){
		if ( !fileExists( arguments.path ) ) {
			throw(
				type    = "Deploybot.EnvFile",
				message = "The env file was not found at #arguments.path#. Create it from .env.example and fill in the production values."
			);
		}
		var bytes = fileReadBinary( arguments.path );
		if ( arrayLen( bytes ) > variables.maxBytes ) {
			throw(
				type    = "Deploybot.TooLarge",
				message = "The env file is #arrayLen( bytes )# bytes. DeployBot accepts at most #variables.maxBytes# bytes (64 KB)."
			);
		}
		return bytes;
	}

	/**
	 * Decodes bytes as UTF-8 text. Use the text for checks only. Send the bytes, not the text.
	 *
	 * @bytes The bytes from readBytes().
	 */
	string function decode( required any bytes ){
		return charsetEncode( arguments.bytes, "utf-8" );
	}

	/**
	 * Returns the key names in the text, in order, without duplicates.
	 *
	 * @text The .env text.
	 */
	array function keyNames( required string text ){
		return variables.parse( arguments.text ).order;
	}

	/**
	 * Returns the key names whose value is blank. For a repeated key, the last line wins.
	 * A value is blank when it is empty, empty quotes (`""` or `''`), or only an inline comment.
	 *
	 * @text The .env text.
	 */
	array function blankKeys( required string text ){
		var entries = variables.parse( arguments.text );
		var blanks  = [];
		for ( var key in entries.order ) {
			if ( entries.blank[ key ] ) {
				blanks.append( key );
			}
		}
		return blanks;
	}

	/**
	 * Returns a starter env file built from .env.example text. Each key line keeps its key and
	 * loses its value, so `export KEY=dev` becomes `export KEY=`. Comments and blank lines stay.
	 * The rest of a multi-line quoted value is dropped. Lines end with LF.
	 *
	 * @exampleText The .env.example text.
	 */
	string function templateFrom( required string exampleText ){
		var out      = [];
		var openQuote = "";
		for ( var line in variables.lines( arguments.exampleText ) ) {
			if ( len( openQuote ) ) {
				// Skip the rest of a multi-line value up to the line that closes its quote.
				if ( find( openQuote, line ) ) {
					openQuote = "";
				}
				continue;
			}
			var match = reFind( variables.keyPattern, line, 1, true );
			if ( match.pos[ 1 ] == 0 ) {
				out.append( line );
				continue;
			}
			var keyEnd = match.pos[ 1 ] + match.len[ 1 ] - 1;
			out.append( reReplace( left( line, keyEnd ), "\s*=$", "=" ) );
			openQuote = unclosedQuote( valueAfterKey( line, match ) );
		}
		return out.toList( chr( 10 ) ) & chr( 10 );
	}

	/**
	 * Returns the quote character that starts a value and is not closed on the same line, or an
	 * empty string.
	 *
	 * @raw The text after the first `=` on a line.
	 */
	private string function unclosedQuote( required string raw ){
		var value = trim( arguments.raw );
		var first = left( value, 1 );
		if ( ( first == '"' || first == "'" ) && !find( first, value, 2 ) ) {
			return first;
		}
		return "";
	}

	/**
	 * Returns true when the raw text after `=` is a blank value.
	 *
	 * @raw The text after the first `=` on a line.
	 */
	boolean function isBlankValue( required string raw ){
		var value = trim( arguments.raw );
		if ( !len( value ) ) {
			return true;
		}
		var first = left( value, 1 );
		if ( first == '"' || first == "'" ) {
			var close = find( first, value, 2 );
			// An unclosed quote starts a multi-line value, so it is not blank.
			return close > 0 && close == 2;
		}
		// An inline comment starts at a # that begins the value or follows whitespace.
		return left( value, 1 ) == "##";
	}

	/**
	 * Parses the text into an ordered struct of key names and a blank flag for each.
	 * The returned struct has the array "order" (key names) and the struct "blank" (key to boolean).
	 *
	 * @text The .env text.
	 */
	private struct function parse( required string text ){
		var order = [];
		var blank = {};
		for ( var line in variables.lines( arguments.text ) ) {
			var match = reFind( variables.keyPattern, line, 1, true );
			if ( match.pos[ 1 ] == 0 ) {
				continue;
			}
			var key = mid( line, match.pos[ 2 ], match.len[ 2 ] );
			if ( !blank.keyExists( key ) ) {
				order.append( key );
			}
			blank[ key ] = isBlankValue( valueAfterKey( line, match ) );
		}
		return { order : order, blank : blank };
	}

	/**
	 * Splits .env text into lines. It removes a byte order mark, accepts CRLF and lone CR, and
	 * drops the empty line after a final line break.
	 *
	 * @text The .env text.
	 */
	private array function lines( required string text ){
		var body = arguments.text;
		// Remove a byte order mark.
		if ( len( body ) && asc( left( body, 1 ) ) == 65279 ) {
			body = right( body, len( body ) - 1 );
		}
		body = body.replace( chr( 13 ) & chr( 10 ), chr( 10 ), "all" ).replace( chr( 13 ), chr( 10 ), "all" );
		var result = body.listToArray( chr( 10 ), true );
		if ( result.len() && !len( result.last() ) ) {
			result.deleteAt( result.len() );
		}
		return result;
	}

	/**
	 * Returns the raw text after the `=` that ends the key match.
	 *
	 * @line  The full line.
	 * @match The reFind result for the key pattern.
	 */
	private string function valueAfterKey( required string line, required struct match ){
		var end = match.pos[ 1 ] + match.len[ 1 ];
		return mid( arguments.line, end, len( arguments.line ) - end + 1 );
	}
}
