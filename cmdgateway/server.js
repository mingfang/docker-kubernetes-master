var express = require('express');
var exec = require('child_process').execFileSync;
var bodyParser = require("body-parser");

var app = express();
app.use(bodyParser.urlencoded({ extended: false }));
app.use(bodyParser.json());

app.get('/kubectl/:args', function(req, res){
    var args = ["--server=http://localhost:8080"];
    var reqArgs = req.params.args.split(" ");
    for(var i=0; i < reqArgs.length; i++){
      args.push(reqArgs[i]);
    }
    var ip = req.headers['x-forwarded-for'] || req.connection.remoteAddress;
    console.log("[" + ip + "] kubectl", args);
    var stdout = exec("kubectl", args).toString();
    res.end(stdout);
});

var server = app.listen(3000, function () {
    var host = server.address().address;
    var port = server.address().port;
    console.log('CmdGateway listening at http://%s:%s', host, port);
});
