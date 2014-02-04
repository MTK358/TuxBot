To get a working, 40MB big whitelist based on the DMOZ directory, run the following command:
bash ./extract-whitelist.sh

---------------------------------------------------------------------------------------------------
The whitelist in whitelist.txt.xz is a converted version of the RDF dump of the dmoz.org directory.
The contents of the directory are published under a CreativeCommons-BY-License:
http://www.dmoz.org/license.html

What we did to get this list:
- we downloaded the content.rdf.u8.gz file available here:
   http://www.dmoz.org/rdf.html --> http://rdf.dmoz.org/rdf/content.rdf.u8.gz
  at 2012-10-08.
- we extracted the file
- we ran the following command:
   cat content.rdf.u8 | grep -E "http://" | cut -d \" -f 2 | cut -d \" -f 2 | cut -d / -f 3 | cut -d . -f 2- | sort | uniq > whitelist.txt
- we opened the file using the Kate text editor, but any other editor will be able to do the following task
- we deleted the first line (empty) and the last few lines (containing some right-to-left characters which we can't use)
- we saved the file
- we compressed it using xz -zkvv9e ./whitelist.txt
...and uploaded it.


If it should be necessary for whatever reason, here is the "required attribution" in HTML format...
<p><table border="0" bgcolor="#336600" cellpadding="3" cellspacing="0">
<tr>
<td>
<table width="100%" cellpadding="2" cellspacing="0" border="0">
<tr align="center">
<td><font face="sans-serif, Arial, Helvetica" size="2" color="#FFFFFF">Help build the largest human-edited directory on the web.</font></td>
</tr>
<tr bgcolor="#CCCCCC" align="center">
<td><font face="sans-serif, Arial, Helvetica" size="2">
<a href="/cgi-bin/add.cgi?where=$cat">Submit a Site</a> -
<a href="/about.html"><b>Open Directory Project</b></a> -
<a href="/cgi-bin/apply.cgi?where=$cat">Become an Editor</a> </font>
</td></tr>
</table>
</td>
</tr>
</table> 
