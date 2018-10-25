import strutils
import os

when defined(posix):
  proc isabs*(path: string): bool =
    path.startswith("/")

  proc join*(p1: string, paths: varargs[string, `$`]): string =
    ## Join two or more pathname components, inserting '/' as needed.
    ## If any component is an absolute path, all previous path components
    ## will be discarded.  An empty last part will result in a path that
    ## ends with a separator.
    ##
    let sep = "/"
    result = p1
    for b in paths:
      if b.startswith(sep):
        result = b
      elif len(result) == 0 or result.endswith(sep):
        result.add(b)
      else:
        result.add(sep & b)

  proc join(paths: seq[string]): string =
    let sep = "/"
    result = paths[0]
    for b in paths[1..^1]:
      if b.startswith(sep):
        result = b
      elif len(result) == 0 or result.endswith(sep):
        result.add(b)
      else:
        result.add(sep & b)

  proc split*(path: string): tuple[head: string, tail: string] =
    ## Split a pathname.  Returns tuple "(head, tail)" where "tail" is
    ## everything after the final slash.  Either part may be empty.
    ##
    let sep = "/"
    let i = path.rfind(sep)
    if i >= 0:
      result.head = path[0..i]
      result.tail = path[i+1..^1]
    else:
      result.head = ""
      result.tail = path
    if len(result.head) > 0 and result.head != sep.repeat(len(result.head)):
      result.head = result.head.strip(leading = false, trailing = true, chars = {sep[0]})

  proc splitext*(path: string): tuple[root: string, ext: string] =
    ## Split the extension from a pathname.
    ##
    ## Extension is everything from the last dot to the end, ignoring
    ## leading dots.  Returns "(root, ext)"; ext may be empty.
    ##
    let sep = "/"
    let extsep = "."

    let sepIndex = path.rfind(sep)
    let dotIndex = path.rfind(extsep)
    if dotIndex > sepIndex:
      # skip all leading dots
      var filenameIndex = sepIndex + 1
      while filenameIndex < dotIndex:
        if path[filenameIndex] != extsep[0]:
          result.root = path[0..dotIndex - 1]
          result.ext = path[dotIndex .. ^1]
          return
        inc(filenameIndex)
    result.root = path
    result.ext = ""

  proc splitdrive*(path: string): tuple[drive: string, path: string] =
    ## Split a pathname into a drive specification and the rest of the
    ## path.  Useful on DOS/Windows/NT; on Unix, the drive is always empty.
    result.drive = ""
    result.path = path


  proc basename*(path: string): string =
    ## Returns the final component of a pathname
    let i = path.rfind("/") + 1
    result = path[i..^1]

  proc dirname*(path: string): string =
    ## Returns the directory component of a pathname
    let sep = "/"
    let i = path.rfind(sep)
    if i >= 0:
      result = path[0..i]
    if len(result) > 0 and result != sep.repeat(len(result)):
      result = result.strip(leading = false, trailing = true, chars = {sep[0]})

  proc normpath*(path: string): string =
    ## Normalize path, eliminating double slashes, etc.
    let sep = "/"
    let empty = ""
    let dot = "."
    let dotdot = ".."

    if path == empty:
      return dot

    var initialSlashes = 0
    if path.startswith(sep):
      initialSlashes = 1
    if initialSlashes == 1:
      if path.startswith(sep.repeat(2)) and not path.startswith(sep.repeat(3)):
        initialSlashes = 2

    var comps = path.split(sep)
    var new_comps: seq[string] = @[]
    for comp in comps:
      if comp == empty or comp == dot:
        continue
      if comp != dotdot or
         (initialSlashes == 0 and len(new_comps) == 0) or
         (len(new_comps) > 0 and new_comps[^1] == dotdot):
        new_comps.add(comp)
      elif len(new_comps) > 0:
        new_comps.setLen(len(new_comps) - 1)
    comps = new_comps
    if initialSlashes > 0:
      result = sep.repeat(initialSlashes)
    result.add(comps.join(sep))
    if result.len == 0:
      result = dot

  proc abspath*(path: string): string =
    ## Return an absolute path.
    if not isabs(path):
      let cwd = getCurrentDir()
      result = join(cwd, path)
    else:
      result = path
    result = normpath(result)

  proc commonprefix(pathList1, pathList2: seq[string]): seq[string] =
    var shorterList: seq[string]
    var longerList: seq[string]
    if len(pathList1) < len(pathList2):
      shorterList = pathList1
      longerList = pathList2
    else:
      shorterList = pathList2
      longerList = pathList1

    for i, path in shorterList:
      if path != longerList[i]:
        return shorterList[0 .. i-1]

    return shorterList

  proc relpath*(path: string, start: string = ""): string =
    ## Return a path relative to start. If start is empty, assume '.'
    ##
    let curdir = "."
    let sep = "/"
    let pardir = ".."

    var start = start
    if start.len == 0:
      start = curdir

    var startList: seq[string] = @[]
    var pathList: seq[string] = @[]

    for x in abspath(start).split(sep):
      if len(x) > 0:
        startList.add(x)
    for x in abspath(path).split(sep):
      if len(x) > 0:
        pathList.add(x)
    echo "startList: ", startList
    echo "pathList:  ", pathList
    echo "commonPrefix: ", commonprefix(startList, pathList)

    let i = len(commonprefix(startList, pathList))
    var relList: seq[string] = @[]
    for x in 1 .. len(startList) - i:
      relList.add(pardir)
    for p in i ..< len(pathList):
      relList.add(pathList[p])

    if len(relList) == 0:
      return curdir
    return join(relList)


when defined(windows):
  proc splitdrive*(path: string): tuple[driveOrUnc: string, path: string] =
    ## Split a pathname into drive/UNC sharepoint and relative path specifiers.
    ## Returns a 2-tuple (drive_or_unc, path); either part may be empty.
    ##
    ## If you assign
    ##  result = splitdrive(p)
    ## It is always true that:
    ##  result[0] + result[1] == p
    ##
    ## If the path contained a drive letter, drive_or_unc will contain everything
    ## up to and including the colon.  e.g. splitdrive("c:/dir") returns ("c:", "/dir")
    ##
    ## If the path contained a UNC path, the drive_or_unc will contain the host name
    ## and share up to but not including the fourth directory separator character.
    ## e.g. splitdrive("//host/computer/dir") returns ("//host/computer", "/dir")
    ##
    ## Paths cannot contain both a drive letter and a UNC path.
    ##
    if len(path) >= 2:
      let sep = "\\"
      let altsep = "/"
      let colon = ":"

      let normp = path.replace(altsep, sep)
      if normp[0..1] == sep.repeat(2) and normp[2..2] != sep:
        # is a UNC path:
        # vvvvvvvvvvvvvvvvvvvv drive letter or UNC path
        # \\machine\mountpoint\directory\etc\...
        #           directory ^^^^^^^^^^^^^^^
        let index = normp.find(sep, 2)
        if index == -1:
          result.driveOrUnc = ""
          result.path = path
          return
        var index2 = normp.find(sep, index + 1)
        # a UNC path can't have two slashes in a row
        # (after the initial two)
        if index2 == index + 1:
          result.driveOrUnc = ""
          result.path = path
          return
        if index2 == -1:
          index2 = len(path)
        result.driveOrUnc = path[0..index2-1]
        result.path = path[index2..^1]
        return
      if normp[1..1] == colon:
        result.driveOrUnc = path[0..1]
        result.path = path[2..^1]
        return
    result.driveOrUnc = ""
    result.path = path


  proc normpath*(path: string): string =
    let sep = "\\"
    let altsep = "/"
    let dot = "."
    let dotdot = ".."
    let empty = ""
    let specialPrefixes = ["\\\\.\\", "\\\\?\\"]

    if path.startswith(specialPrefixes[0]) or
       path.startswith(specialPrefixes[1]):
      # in the case of paths with these prefixes:
      # \\.\ -> device names
      # \\?\ -> literal paths
      # do not do any normalization, but return the path unchanged
      return path

    var path = path.replace(altsep, sep)
    var prefix: string
    (prefix, path) = splitdrive(path)

    # collapse initial backslashes
    if path.startswith(sep):
      prefix.add(sep)
      path = path.strip(trailing = false, chars = {sep[0]})

    let comps = path.split(sep)
    var new_comps: seq[string] = @[]

    for i, comp in comps:
      #echo "i: ", " comp: ", comp, " new: ", new_comps, " prefix: ", prefix
      if comp == empty or comp == dot:
        continue
      if comp == dotdot:
        if len(new_comps) > 0 and new_comps[^1] != dotdot:
          new_comps.setLen(len(new_comps) - 1)
        elif len(new_comps) == 0 and prefix.endswith(sep):
          continue
        else:
          new_comps.add(comp)
      else:
        new_comps.add(comp)

    result = prefix
    result.add(new_comps.join(sep))
    if result.len == 0:
      result = dot

when isMainModule:
  when defined(posix):
    block NimTests:
      doAssert normpath("/foo/../bar") == "/bar"
      doAssert normpath("foo/../bar") == "bar"

      doAssert normpath("/f/../bar///") == "/bar"
      doAssert normpath("f/..////bar") == "bar"

      doAssert normpath("../bar") == "../bar"
      doAssert normpath("/../bar") == "/bar"

      doAssert normpath("foo/../../bar/") == "../bar"
      doAssert normpath("./bla/blob/") == "bla/blob"
      doAssert normpath(".hiddenFile") == ".hiddenFile"
      doAssert normpath("./bla/../../blob/./zoo.nim") == "../blob/zoo.nim"

      doAssert normpath("C:/file/to/this/long") == "C:/file/to/this/long"
      doAssert normpath("") == "."
      doAssert normpath("foobar") == "foobar"
      doAssert normpath("f/////////") == "f"

    block PythonTests:
      doAssert normpath("") == "."
      doAssert normpath("/") == "/"
      doAssert normpath("//") == "//"
      doAssert normpath("///") == "/"
      doAssert normpath("///foo/.//bar//") == "/foo/bar"
      doAssert normpath("///foo/.//bar//.//..//.//baz") == "/foo/baz"
      doAssert normpath("///..//./foo/.//bar") == "/foo/bar"

  when defined(windows):
    doAssert splitDrive("c:\\foo\\bar") == ("c:", "\\foo\\bar")
    doAssert splitdrive("c:/foo/bar") == ("c:", "/foo/bar")
    doAssert splitdrive("\\\\conky\\mountpoint\\foo\\bar") == ("\\\\conky\\mountpoint", "\\foo\\bar")
    doAssert splitdrive("//conky/mountpoint/foo/bar") == ("//conky/mountpoint", "/foo/bar")
    doAssert splitdrive("\\\\\\conky\\mountpoint\\foo\\bar") == ("", "\\\\\\conky\\mountpoint\\foo\\bar")
    doAssert splitdrive("///conky/mountpoint/foo/bar") == ("", "///conky/mountpoint/foo/bar")
    doAssert splitdrive("\\\\conky\\\\mountpoint\\foo\\bar") == ("", "\\\\conky\\\\mountpoint\\foo\\bar")
    doAssert splitdrive("//conky//mountpoint/foo/bar") == ("", "//conky//mountpoint/foo/bar")
    doAssert splitdrive("//conky/MOUNTPOİNT/foo/bar") == ("//conky/MOUNTPOİNT", "/foo/bar")

    doAssert normpath("A//////././//.//B") == r"A\B"
    doAssert normpath("A/./B") == r"A\B"
    doAssert normpath("A/foo/../B") == r"A\B"
    doAssert normpath("C:A//B") == r"C:A\B"
    doAssert normpath("D:A/./B") == r"D:A\B"
    doAssert normpath("e:A/foo/../B") == r"e:A\B"

    doAssert normpath("C:///A//B") == r"C:\A\B"
    doAssert normpath("D:///A/./B") == r"D:\A\B"
    doAssert normpath("e:///A/foo/../B") == r"e:\A\B"

    doAssert normpath("..") == r".."
    doAssert normpath(".") == r"."
    doAssert normpath("") == r"."
    doAssert normpath("/") == "\\"
    doAssert normpath("c:/") == "c:\\"
    doAssert normpath("/../.././..") == "\\"
    doAssert normpath("c:/../../..") == "c:\\"
    doAssert normpath("../.././..") == r"..\..\.."
    doAssert normpath("K:../.././..") == r"K:..\..\.."
    doAssert normpath("C:////a/b") == r"C:\a\b"
    doAssert normpath("//machine/share//a/b") == r"\\machine\share\a\b"

    doAssert normpath("\\\\.\\NUL") == r"\\.\NUL"
    doAssert normpath("\\\\?\\D:/XY\\Z") == r"\\?\D:/XY\Z"
