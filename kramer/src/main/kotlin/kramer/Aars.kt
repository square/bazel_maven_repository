/*
 * Copyright (C) 2020 Square, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License
 * is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
 * or implied. See the License for the specific language governing permissions and limitations under
 * the License.
 *
 */
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

private val parserFactory = SAXParserFactory.newInstance()

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
