import java.io.File;
import org.apache.lucene.index.IndexReader;
import org.apache.lucene.index.Term;
import org.apache.lucene.index.TermDocs;
import org.apache.lucene.index.TermEnum;
import org.apache.lucene.store.FSDirectory;

// Read-only checks on Nexus index working folders. Build against the indexer cli jar (Lucene 3.0.3).
//   CountIndex DIR                  counts
//   CountIndex --subset BEFORE AFTER  counts artifacts in BEFORE that are missing from AFTER
//   CountIndex --has DIR LISTFILE     checks that each repository path in LISTFILE is in the index
public class CountIndex
{
    public static void main( String[] args )
        throws Exception
    {
        if ( args[0].equals( "--has" ) )
        {
            has( args[1], args[2] );
            return;
        }
        if ( args[0].equals( "--subset" ) )
        {
            subset( args[1], args[2] );
            return;
        }
        IndexReader r = open( args[0] );
        System.out.println( "maxDoc=" + r.maxDoc() + " live=" + r.numDocs() + " luceneDeleted=" + r.numDeletedDocs()
            + " artifacts(u)=" + count( r, "u" ) + " deleteMarkers(del)=" + count( r, "del" ) );
        r.close();
    }

    private static IndexReader open( String dir )
        throws Exception
    {
        return IndexReader.open( FSDirectory.open( new File( dir ) ), true );
    }

    private static long count( IndexReader r, String field )
        throws Exception
    {
        TermEnum te = r.terms( new Term( field, "" ) );
        long n = 0;
        while ( te.term() != null && te.term().field().equals( field ) )
        {
            n++;
            if ( !te.next() ) break;
        }
        te.close();
        return n;
    }

    // Both term lists are sorted, so one pass over each is enough.
    private static void subset( String beforeDir, String afterDir )
        throws Exception
    {
        IndexReader b = open( beforeDir ), a = open( afterDir );
        TermEnum tb = b.terms( new Term( "u", "" ) ), ta = a.terms( new Term( "u", "" ) );
        long missing = 0;
        boolean aMore = ta.term() != null && ta.term().field().equals( "u" );
        while ( tb.term() != null && tb.term().field().equals( "u" ) )
        {
            String want = tb.term().text();
            while ( aMore && ta.term().text().compareTo( want ) < 0 )
            {
                aMore = ta.next() && ta.term().field().equals( "u" );
            }
            if ( !aMore || !ta.term().text().equals( want ) )
            {
                missing++;
            }
            if ( !tb.next() ) break;
        }
        System.out.println( "missingFromAfter=" + missing );
        b.close();
        a.close();
    }

    // Index key (field "u"): group|artifact|version|classifier-or-NA, with |extension added for some files.
    // A listed file counts as present when the index holds an entry for its group, artifact, version and classifier.
    private static String keyFor( String path )
    {
        String[] p = path.split( "/" );
        int n = p.length;
        String file = p[n - 1], version = p[n - 2], artifact = p[n - 3];
        StringBuilder group = new StringBuilder();
        for ( int i = 0; i < n - 3; i++ )
        {
            group.append( i > 0 ? "." : "" ).append( p[i] );
        }
        String prefix = artifact + "-" + version;
        if ( !file.startsWith( prefix ) ) return null;
        String rest = file.substring( prefix.length() );
        String classifier = "NA";
        if ( rest.startsWith( "-" ) )
        {
            classifier = rest.substring( 1, rest.indexOf( '.' ) );
        }
        return group + "|" + artifact + "|" + version + "|" + classifier;
    }

    private static void has( String dir, String listFile )
        throws Exception
    {
        IndexReader r = open( dir );
        long present = 0, absent = 0, unparsed = 0;
        for ( String path : new String( java.nio.file.Files.readAllBytes( new File( listFile ).toPath() ) ).split( "\\s+" ) )
        {
            if ( path.isEmpty() ) continue;
            String key = keyFor( path );
            if ( key == null ) { unparsed++; continue; }
            // Either the exact key, or a key followed by '|'. A sibling such as "x-musl|jar" sorts before "x|jar".
            TermEnum te = r.terms( new Term( "u", key ) );
            Term t = te.term();
            boolean found = t != null && t.field().equals( "u" ) && t.text().equals( key );
            te.close();
            if ( !found )
            {
                te = r.terms( new Term( "u", key + "|" ) );
                t = te.term();
                found = t != null && t.field().equals( "u" ) && t.text().startsWith( key + "|" );
                te.close();
            }
            if ( found ) present++; else { absent++; if ( absent <= 5 ) System.out.println( "absent: " + path ); }
        }
        System.out.println( "present=" + present + " absent=" + absent + " unparsed=" + unparsed );
        r.close();
    }
}
