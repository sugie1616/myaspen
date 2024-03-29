#!/usr/local/bin/konoha

/*
 * aspen.k : small script for invoking konoha
 * (c) shinpei_NKT, utrhira, chen_ji
 */

include "storage.k";
include "login.k";
//include "bugreporter.k"
using konoha.signal.*;
using konoha.cookie.*;
using konoha.proc.*;

KONOHA_PATH = "";
GIT_PATH    = "";
BASE_PATH   = "";
SCRIPT_DIR  = "";
BUG_DIR     = "";
TMP_DIR     = "";

string admin_menu = """
<!DOCTYPE html>
<html lang="ja">
<head>
	<meta charset="UTF-8">
	<title>Admin Menu - Aspen</title>
	<style>
	body { padding: 1em; margin: auto; }
	table, td, th { border: 1px black solid; border-spacing: 0px;}
	td, th { padding: 3px; }
	</style>
</head>
<body>
	<header>
		<h1>Admin Menu</h1>
	</header>
	<form action="aspen.k" method="POST">
		<input type="hidden" name="type" value="update">
		<table>
			<caption>
				<strong>You can modify user roles by filling the form below.</strong>
			</caption>
			<thead>
				<tr><th>User ID</th><th>Screen Name</th><th>Role</th><th>New Role</th></tr>
			</thead>
			<tbody>
				%body%
			</tbody>
		</table>
		<p><input type="submit" value="Update Roles">
		<input type="reset" value="Reset"></p>
		<p><a href="doc">Back to editor</a></p>
	</form>
</body>
</html>"""

void alarm_handler(int signum) {
	throw new Security!!("too long");
}

class Aspen
{
	Storage storage;
	string uid;
	string base;
	string bug_dir;
	string scr_dir;
	string tmp_dir;
	string konoha_path;
	string git_path;

	Aspen(string base_path, string bug_dir, string script_dir, string tmp_dir, string konoha_path, string git_path) {
		_storage = new Storage();
		_uid = "";
		_base = base_path;
		_bug_dir = bug_dir;
		_scr_dir = script_dir;
		_tmp_dir = tmp_dir;
		_konoha_path = konoha_path;
		_git_path = git_path;
	}

	void printText(string text) {
		OUT << "Content-Type: text/plain" + EOL << EOL;
		OUT << text;
		OUT.flush();
	}

	void deleteCookie(string key) {
		string past = "Thu, 01 Jan 1970 00:00:00 GMT";
		Cookie cookie = new Cookie();
		cookie[key] = "";
		cookie[key]["path"] = "/";
		cookie[key]["expires"] = past;
		OUT << cookie.dump();
	}

	void saveCookie(string key, string val) {
		Cookie cookie = new Cookie();
		cookie[key] = val;
		cookie[key]["path"] = "/";
		OUT << cookie.dump();
	}

	void auth(string sid) {
		uid = storage.getUid(sid);
		if (uid == "") {
			throw new Script!!("Authentication failed.");
		}
	}

	string getKonohaRevision() {
		string cmd = "svnversion " + konoha_path;
		//return exec(cmd).split("\n")[0];
		string[] map = [];
		map = exec(cmd).split("\n");
		string rev = map[0];
		return rev;
	}

	string getAspenVersion() {
		string cmd = "git --git-dir=" + git_path + " log -1 --format=\"%h\"";
		//return exec(cmd).split("\n")[0];
		string[] map = [];
		map = exec(cmd).split("\n");
		string aver = map[0];
		return aver;
	}

	string getLoadAverage() {
		string cmd = "w";
		//string line = exec(cmd).split("\n")[0];
		//return line.substring(line.indexOf("load"));
		string[] map = [];
		map = exec(cmd).split("\n");
		string lavg = map[0];
		return lavg.substring(lavg.indexOf("load"));
	}

	string escape(string text)
	{
		text = text.replace($/&/g, "&amp;");
		text = text.replace($/</g, "&lt;");
		text = text.replace($/>/g, "&gt;");
		text = text.replace($/"/g, "&quot;");
		text = text.replace($/ /g, "&nbsp;");
		text = text.replace($/\r\n/g, "<br>");
		text = text.replace($/(\n|\r)/g, "<br>");
		return text;
	}

	void evalScript(string scr_name, string scr_body) {
		storeScript(scr_name, scr_body);
		string usr_path = base + "/" + scr_dir + "/" + uid;

		int starttime = getTime();
		string[] cmd = [];
		cmd.add("/usr/local/bin/konoha");
		cmd.add("-a");
		cmd.add("--enforce-security=" + storage.getRole(uid));
		cmd.add(usr_path + "/" + scr_name);

		Subprocess p = new Subprocess(cmd);
		InputStream stdout = p.getInputStream();
		InputStream stderr = p.getErrorInputStream();
		string tmp_path = base + "/" + tmp_dir;
		string outfilename = tmp_path + "/" + uid + ".out";
		string errfilename = tmp_path + "/" + uid + ".err";
		OutputStream outfile = new OutputStream(outfilename, "w");
		OutputStream errfile = new OutputStream(errfilename, "w");

		Signal.signal(Signal.SIGALRM, alarm_handler);
		Signal.alarm(3 * 60) // 3 minutes
		int max_size = 1024 * 50; // 50 MB

		try {
			int size = 0;
			while (!p.poll()) {
				foreach (string line in stdout) {
					size += line.getSize();
					if (size < max_size) {
						outfile << line << EOL;
						outfile.flush();
					} else {
						throw new Script!!("too long output");
					}
				}
			}
			outfile.close();
			foreach (string line in stderr) {
				errfile << line << EOL;
			}
			Signal.alarm(0);
		} catch (Security!! e) {
			// timeout
			p.terminate();
			errfile << "KonohaScript was terminated because the program was ";
			errfile << "running too long time (more than 3 minutes).";
			errfile.close();
		} catch (Script!! e) {
			p.terminate();
			errfile << "KonohaScript was terminated because the output text ";
			errfile << "is too long (over 50 KB).";
		}

		int exetime = getTime() - starttime;
		string krev = getKonohaRevision();
		string aver = getAspenVersion();
		string load = getLoadAverage();
		int r = p.wait();
		switch (r) {
			case 0:
				break;
			default:
				errfile << "Konoha exited unexpectedly with signal: " + r;
				break;
		}
		errfile.close();

		string msg = "time: " + ((to float)exetime / 1000) + "<br>";
		msg += load + "<br>";
		msg += "KonohaScript revision: " + krev + "<br>";
		msg += "Aspen version: " + aver + "<br>";
		OUT << "Content-Type: application/json;charset=UTF-8" + EOL << EOL;
		OUT << "{\"item\": [{\"key\": \"stderr\", \"value\": \"";
		foreach (string s in new InputStream(errfilename, "r")) {
			OUT << escape(s) << "<br>";
		}
		OUT << "\"}, {\"key\": \"stdout\", \"value\": \"";
		foreach (string s in new InputStream(outfilename, "r")) {
			OUT << escape(s) << "<br>";
		}
		OUT << "\"}, {\"key\": \"message\", \"value\": \"" + msg + "\"}]}" << EOL;
	}

	void signoutOauth() {
		deleteCookie("SID");
		OUT << EOL;
	}

	void printScript(string scr_name) {
		OUT << "Content-Type: text/plain" + EOL << EOL;
		string scr_path = base + "/" + scr_dir + "/" + uid + "/" + scr_name;
		InputStream is = new InputStream(scr_path, "r");
		if (is != null) {
			foreach (string s in is) {
				OUT << s << EOL;
			}
		}
	}

	void printFileList() {
		string usr_path = base + "/" + scr_dir + "/" + uid;
		string[] files = exec("ls " + usr_path).split("\n");
		files.pop();

		OUT << "Content-Type: application/json;charset=UTF-8" + EOL << EOL;
		OUT << "{\"item\": [[\"/\", [], [\"";
		for (int i = 0; i < |files|; i++) {
			if (i == |files| - 1) {
				OUT << files[i] + "\"";
			} else {
				OUT << files[i] + "\", \"";
			}
		}
		OUT << "]]]}";
		OUT.flush();
	}

	void storeScript(string scr_name, string scr_body) {
		string usr_path = base + "/" + scr_dir + "/" + uid;
		if (new InputStream(usr_path, "r") == null) {
			exec("mkdir " + usr_path);
		}
		string scr_path = usr_path + "/" + scr_name;
		OutputStream script = new OutputStream(scr_path, "w");
		script << scr_body;
		script.close();
	}

	void showAdminMenu() {
		OUT << "Content-Type: text/html" + EOL << EOL;
		Tuple<string, string, string>[] userlist = storage.getUserList();
		string tbl_body = "";
		foreach (Tuple<string, string, string> t in userlist) {
			tbl_body += "<tr><td>" + t[0] + "</td><td>" + t[1] + "</td><td>";
			tbl_body += t[2] + "</td><td><input type=\"text\" name=\"";
			tbl_body += t[0] + "\" size=\"30\"></td>\n";
		}
		OUT << admin_menu.replace($/%body%/, tbl_body);
		OUT.flush();
	}
}

void main(string[] args)
{
	//OUT << a.cookie << EOL;
	//OUT << $env.QUERY_STRING << EOL;
	////string method = $env."REQUEST_METHOD";
	////OUT << method << EOL;
	//OUT << "Content-Type: text/html\n" << EOL;
	Aspen a = new Aspen(BASE_PATH, BUG_DIR, SCRIPT_DIR, TMP_DIR, KONOHA_PATH, GIT_PATH);
	Cookie cookie = new Cookie($env.HTTP_COOKIE);
	Map<string,string> field;
	string method = $env.REQUEST_METHOD;
	if (method == "POST") {
		field = Cgi.parseQuery(IN.readLine());
		switch (field["type"]) {
		case "eval":
			a.auth(cookie["SID"]["val"]);
			a.evalScript(field["name"], field["kscript"]);
			break;
		case "save":
			a.auth(cookie["SID"]["val"]);
			a.storeScript(field["name"], field["kscript"]);
			a.printText("Script \"" + field["name"] + "\" was saved successfully.");
			break;
		case "update":
			a.auth(cookie["SID"]["val"]);
			foreach (string key in field.keys()) {
				string val = field[key];
				if (key != "type" && val != "") {
					a.getStorage().updateUserRole(key, val);
				}
			}
			OUT << "Location: aspen.k?type=admin" + EOL << EOL;
			break;
		default:
			throw new Script!!("POST does not have type " + field["type"] + ".");
			break;
		}
	} else if (method == "GET") {
		field = Cgi.parseQuery($env.QUERY_STRING);
		switch (field["type"]) {
		case "signout":
			a.signoutOauth();
			break;
		case "load":
			a.auth(cookie["SID"]["val"]);
			a.printScript(field["file"]);
			break;
		case "open":
			a.auth(cookie["SID"]["val"]);
			a.printFileList();
			break;
		case "getUID":
			a.auth(cookie["SID"]["val"]);
			a.printText(a.getUid());
			break;
		case "admin":
			a.auth(cookie["SID"]["val"]);
			a.showAdminMenu();
			break;
		default:
			throw new Script!!("GET does not have type " + field["type"] + ".");
			break;
		}
	} else {
		throw new Script!!("No such method.");
	}
}
