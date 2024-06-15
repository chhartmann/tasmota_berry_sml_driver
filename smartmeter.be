import strict
import smlparser
import json

class Smartmeter
  var read_buf
  var parse_buf
  var lock_parse_buf
  var parser
  var values
  var ser

  def init()
    self.read_buf = bytes()
    self.parse_buf = bytes()
    self.parser = smlparser.SmlParser()
    self.values = "{}"
    self.lock_parse_buf = false
    self.ser = serial(5, 17, 9600, serial.SERIAL_8N1)
  end

  def read_data()
    var parse_buf_ready = false
    if (self.ser.available() > 0)
      self.read_buf += self.ser.read()
      if (self.read_buf.size() > 1500)
        if (self.lock_parse_buf == false)
          self.lock_parse_buf = true
          self.parse_buf = self.read_buf.copy()
          parse_buf_ready = true
        end
        self.read_buf.clear()
      end
    end
    return parse_buf_ready
  end

  def web_sensor()
    var val = json.load(self.values)
    tasmota.web_send("<table border=\"1\"><tr><th>Datapoint</th><th>Value</th><th>Scaler</th></tr>");
    for k : val.keys()
      tasmota.web_send(f"<tr><td>{k}</td><td>{val[k]['value']} {val[k]['unit']}</td><td>{val[k]['scaler']}</td></tr>"); 
    end
    tasmota.web_send("</table>");
  end
  
  def every_50ms()
    if (self.read_data())
      if (self.parser.parse(self.parse_buf))
        self.values = json.dump(self.parser.values)
        tasmota.publish_result(self.values, "data")
      end
      self.lock_parse_buf = false
    end
  end

end

var smldriver = Smartmeter()
tasmota.add_driver(smldriver)
