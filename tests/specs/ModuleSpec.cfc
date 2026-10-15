/** Checks the module name, package exclusions, and registered commands. */
component extends="tests.support.BaseSpec" {

	function run(){
		describe( "Module", function(){
			it( "uses its package slug as the CommandBox module name", function(){
				var packageData  = deserializeJSON( fileRead( repoRoot() & "/box.json" ) );
				var moduleConfig = createObject( "component", "commandbox-deploybot.ModuleConfig" );

				expect( packageData.type ).toBe( "commandbox-modules" );
				expect( packageData.slug ).toBe( "commandbox-deploybot" );
				expect( moduleConfig.cfmapping ).toBe( packageData.slug );
				expect( moduleConfig.modelNamespace ).toBe( packageData.slug );
			} );

			it( "excludes tests and temporary files from the package", function(){
				var ignore = arrayToList( deserializeJSON( fileRead( repoRoot() & "/box.json" ) ).ignore );
				expect( ignore ).toInclude( "/tests/" );
				expect( ignore ).toInclude( "/testbox/" );
				expect( ignore ).toInclude( "/.test-work/" );
				expect( ignore ).toInclude( "/release.json" );
			} );

			it( "keeps every shipped file out of its own ignore list", function(){
				var ignore  = deserializeJSON( fileRead( repoRoot() & "/box.json" ) ).ignore;
				var matcher = application.wirebox.getInstance( "PathPatternMatcher@globber" );
				for ( var shipped in [ "models/", "commands/", "commands/deploybot/", "commands/deploybot/env/push.cfc", "ModuleConfig.cfc", "box.json" ] ) {
					expect( matcher.matchPatterns( ignore, shipped ) ).toBeFalse( "#shipped# must not be ignored" );
				}
			} );

			it( "registers all deploybot commands", function(){
				var hierarchy = application.wirebox.getInstance( "CommandService" ).getCommandHierarchy();
				expect( hierarchy ).toHaveKey( "deploybot" );
				expect( commandNames( hierarchy.deploybot ) ).toBe( "env,token" );
				expect( commandNames( hierarchy.deploybot.env ) ).toBe( "check,push" );
				expect( commandNames( hierarchy.deploybot.token ) ).toBe( "clear,set" );
			} );

			it( "keeps the push command parameters and defaults", function(){
				var names = [];
				for ( var parameter in meta( "commands.deploybot.env.push" ).functions.filter( function( f ){
					return f.name == "run";
				} )[ 1 ].parameters ) {
					names.append( parameter.name & "=" & parameter.default );
				}
				expect( names.toList() ).toBe( "force=false,yes=false,dryRun=false" );
			} );
		} );
	}

	/** Returns the sorted, comma-separated names in a command hierarchy level. */
	private string function commandNames( required struct level ){
		var names = [];
		for ( var key in arguments.level ) {
			if ( left( key, 1 ) != "$" ) {
				names.append( key );
			}
		}
		names.sort( "textnocase" );
		return names.toList();
	}
}
