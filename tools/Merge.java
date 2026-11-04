import java.io.*; import java.nio.file.*; import java.util.*; import java.util.regex.*;
import org.apache.maven.artifact.versioning.DefaultArtifactVersion;
public class Merge {
  record E(String g, String a, String v, String block) {}
  static final Pattern ARCH = Pattern.compile("<archetype>.*?</archetype>", Pattern.DOTALL);
  static String tag(String b, String t) { Matcher m = Pattern.compile("<" + t + ">(.*?)</" + t + ">", Pattern.DOTALL).matcher(b); return m.find() ? m.group(1) : ""; }
  static List<E> read(String p) throws IOException {
    List<E> out = new ArrayList<>(); Matcher m = ARCH.matcher(Files.readString(Path.of(p)));
    while (m.find()) { String b = m.group(); out.add(new E(tag(b,"groupId"), tag(b,"artifactId"), tag(b,"version"), b)); } return out; }
  public static void main(String[] args) throws IOException {
    Map<String,E> all = new LinkedHashMap<>();
    for (E e : read(args[0])) all.put(e.g+":"+e.a+":"+e.v, e);
    int added = 0; for (E e : read(args[1])) if (all.putIfAbsent(e.g+":"+e.a+":"+e.v, e) == null) added++;
    List<E> list = new ArrayList<>(all.values());
    list.sort(Comparator.comparing(E::g).thenComparing(E::a).thenComparing((x, y) -> new DefaultArtifactVersion(y.v).compareTo(new DefaultArtifactVersion(x.v))));
    StringBuilder sb = new StringBuilder("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<archetype-catalog>\n  <archetypes>\n");
    for (E e : list) sb.append("    ").append(e.block).append("\n");
    sb.append("  </archetypes>\n</archetype-catalog>\n");
    Files.writeString(Path.of(args[2]), sb.toString());
    System.err.println("old=" + (all.size() - added) + " new=" + added + " total=" + all.size());
  }
}
