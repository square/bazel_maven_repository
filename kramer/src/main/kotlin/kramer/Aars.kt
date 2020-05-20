package kramer

import org.xml.sax.Attributes
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler
import java.io.IOException
import java.net.URI
import java.nio.file.FileSystemAlreadyExistsException
import java.nio.file.FileSystems
import java.nio.file.Files
import java.nio.file.Path
import javax.xml.parsers.SAXParserFactory

@Throws(IOException::class)
internal fun extractPackageFromManifest(fromZip: URI): String? {
  try {
    FileSystems.newFileSystem(fromZip, emptyMap<String, Any>())
  } catch (e: FileSystemAlreadyExistsException) {
    FileSystems.getFileSystem(fromZip)
  }
    .rootDirectories
    .firstOrNull()
    ?.let { root: Path ->
      Files.walk(root)
        .filter { path -> path.toString() == "/AndroidManifest.xml" }
        .findFirst()
        .orElse(null)
        ?.let { path ->
          val xmlText = Files.readAllLines(path).joinToString("")
          val parserFactory = SAXParserFactory.newInstance()
          // instancing the SAXParser class
          val saxParser = parserFactory.newSAXParser()
          var customPackage: String? = null
          val handler = object : DefaultHandler() {
            @Throws(SAXException::class)
            override fun startElement(
              uri: String,
              localName: String,
              qName: String,
              attributes: Attributes
            ) {
              if (qName == "manifest" || localName == "manifest") {
                customPackage = attributes.getValue("", "package")
              }
            }
          }
          saxParser.parse(xmlText.byteInputStream(), handler)
          return customPackage
        }
    }
  return null
}
