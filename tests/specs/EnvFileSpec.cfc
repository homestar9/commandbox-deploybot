/** Checks env file key parsing, blank value detection, and byte-faithful reading. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "EnvFile", function(){
			beforeEach( function(){
				envFile = model( "EnvFile" );
			} );

			it( "reads KEY= and export KEY= lines and skips comments and blank lines", function(){
				var text = "## comment" & chr( 10 ) & "APP_NAME=x" & chr( 10 ) & chr( 10 ) & "export API_KEY=abc" & chr( 10 )
					& "  SPACED = 1" & chr( 10 ) & "## HIDDEN=1" & chr( 10 ) & "not a key line" & chr( 10 ) & "1BAD=2";
				expect( envFile.keyNames( text ) ).toBe( [ "APP_NAME", "API_KEY", "SPACED" ] );
			} );

			it( "tolerates CRLF, lone CR, and a byte order mark", function(){
				var text = chr( 65279 ) & "FIRST=1" & chr( 13 ) & chr( 10 ) & "SECOND=2" & chr( 13 ) & "THIRD=3";
				expect( envFile.keyNames( text ) ).toBe( [ "FIRST", "SECOND", "THIRD" ] );
			} );

			it( "lists a repeated key once", function(){
				expect( envFile.keyNames( "A=1" & chr( 10 ) & "B=2" & chr( 10 ) & "A=3" ) ).toBe( [ "A", "B" ] );
			} );

			it( "detects blank values, including empty quotes and comment-only values", function(){
				var lines = [
					"EMPTY=",
					"SPACES=   ",
					'DQ=""',
					"SQ=''",
					"COMMENT= ## nothing here",
					'DQ_COMMENT="" ## nothing',
					"export EXPORTED=",
					"FULL=value",
					'QUOTED="value"',
					"HASH_INSIDE=abc ## trailing",
					'SPACE_QUOTED=" "'
				];
				var blanks = envFile.blankKeys( lines.toList( chr( 10 ) ) );
				expect( blanks ).toBe( [ "EMPTY", "SPACES", "DQ", "SQ", "COMMENT", "DQ_COMMENT", "EXPORTED" ] );
			} );

			it( "uses the last line for a repeated key when it decides what is blank", function(){
				expect( envFile.blankKeys( "A=1" & chr( 10 ) & "A=" ) ).toBe( [ "A" ] );
				expect( envFile.blankKeys( "A=" & chr( 10 ) & "A=1" ) ).toBe( [] );
			} );

			it( "does not treat an unclosed quote as blank", function(){
				expect( envFile.isBlankValue( '"' ) ).toBeFalse();
				expect( envFile.isBlankValue( '"abc' ) ).toBeFalse();
			} );

			it( "builds a starter file with every value removed", function(){
				var text = chr( 65279 ) & "## App settings" & chr( 13 ) & chr( 10 )
					& "APP_NAME=#secretValue#" & chr( 13 ) & chr( 10 )
					& chr( 13 ) & chr( 10 )
					& "  export API_KEY = '#secretValue#' ## inline" & chr( 13 ) & chr( 10 )
					& "not a key line" & chr( 13 ) & chr( 10 )
					& "EMPTY=";
				expect( envFile.templateFrom( text ) ).toBe(
					"## App settings" & chr( 10 ) & "APP_NAME=" & chr( 10 ) & chr( 10 ) & "  export API_KEY=" & chr( 10 ) & "not a key line" & chr( 10 ) & "EMPTY=" & chr( 10 )
				);
			} );

			it( "drops the rest of a multi-line value from the starter file", function(){
				var text = "CERT=""-----BEGIN" & chr( 10 ) & "#secretValue#" & chr( 10 ) & "-----END""" & chr( 10 ) & "NEXT=1" & chr( 10 );
				expect( envFile.templateFrom( text ) ).toBe( "CERT=" & chr( 10 ) & "NEXT=" & chr( 10 ) );
			} );

			it( "reads the file as raw bytes and keeps the byte order mark and CRLF", function(){
				var root = createTempProject();
				try {
					var path  = root & "/.env.production";
					var bytes = charsetDecode( chr( 65279 ) & "A=1" & chr( 13 ) & chr( 10 ), "utf-8" );
					fileWrite( path, bytes );
					var read = envFile.readBytes( path );
					expect( arrayLen( read ) ).toBe( 3 + 3 + 2 );
					expect( bitAnd( read[ 1 ], 255 ) ).toBe( 239 );
					expect( bitAnd( read[ 2 ], 255 ) ).toBe( 187 );
					expect( bitAnd( read[ 3 ], 255 ) ).toBe( 191 );
					expect( bitAnd( read[ 7 ], 255 ) ).toBe( 13 );
				} finally {
					deleteDirectory( root );
				}
			} );

			it( "stops with Deploybot.EnvFile when the file is missing", function(){
				expect( function(){
					envFile.readBytes( repoRoot() & "/.test-work/does-not-exist.env" );
				} ).toThrow( type = "Deploybot.EnvFile", regex = "not found" );
			} );

			it( "accepts exactly 64 KB and rejects one byte more", function(){
				var root = createTempProject();
				try {
					var path = root & "/big.env";
					fileWrite( path, repeatString( "a", envFile.maxBytes() ) );
					expect( arrayLen( envFile.readBytes( path ) ) ).toBe( 65536 );

					fileWrite( path, repeatString( "a", envFile.maxBytes() + 1 ) );
					expect( function(){
						envFile.readBytes( path );
					} ).toThrow( type = "Deploybot.TooLarge", regex = "64 KB" );
				} finally {
					deleteDirectory( root );
				}
			} );
		} );
	}
}
