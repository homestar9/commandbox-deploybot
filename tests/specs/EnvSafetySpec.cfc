/** Checks the warnings about where the env file lives in git. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "EnvSafety", function(){
			beforeEach( function(){
				root   = createTempProject();
				lines  = [];
				writeBoxJson( root );
				safety = prepareMock( model( "EnvSafety" ) );
				safety.$property( propertyName = "print", propertyScope = "variables", mock = createRecordingPrinter( lines ) );
			} );

			afterEach( function(){
				deleteDirectory( root );
			} );

			it( "says nothing for an ignored file", function(){
				stubGit();
				var result = safety.check( loadConfig( root ) );
				expect( result.tracked ).toBeFalse();
				expect( lines ).toBe( [] );
			} );

			it( "explains how to fix a tracked file", function(){
				stubGit( { tracked : true } );
				expect( safety.check( loadConfig( root ) ).tracked ).toBeTrue();
				var output = lines.toList( chr( 10 ) );
				expect( output ).toInclude( ".env.production is tracked by git" );
				expect( output ).toInclude( "git rm --cached .env.production" );
			} );

			it( "warns about a file that .gitignore does not cover", function(){
				stubGit( { ignored : false } );
				safety.check( loadConfig( root ) );
				expect( lines.toList( chr( 10 ) ) ).toInclude( "not covered by .gitignore" );
			} );

			it( "skips the git checks outside a repository or without git", function(){
				stubGit( { repository : false, ignored : false } );
				safety.check( loadConfig( root ) );
				stubGit( { known : false, ignored : false } );
				safety.check( loadConfig( root ) );
				expect( lines ).toBe( [] );
			} );
		} );
	}
}
