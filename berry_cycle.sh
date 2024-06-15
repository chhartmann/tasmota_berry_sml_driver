TASMOTA_HOST=SmlTestTasmota
curl -s -o /dev/null "http://$TASMOTA_HOST/ufsd?delete=/smlparser.be"; echo
curl -s -o /dev/null "http://$TASMOTA_HOST/ufsd?delete=/smlparser.ber"; echo
curl -s -o /dev/null "http://$TASMOTA_HOST/ufsd?delete=/smartmeter.be"; echo
curl -s -o /dev/null "http://$TASMOTA_HOST/ufsd?delete=/smartmeter.ber"; echo
curl -v -s -o /dev/null -F "file=@./smlparser.be" "http://$TASMOTA_HOST/ufsu"; echo
curl -v -s -o /dev/null -F "file=@./smartmeter.be" "http://$TASMOTA_HOST/ufsu"; echo
curl http://$TASMOTA_HOST/cm --data-urlencode 'cmnd=brrestart'; echo
sleep 2
curl http://$TASMOTA_HOST/cm --data-urlencode 'cmnd=br load("smartmeter")'; echo
