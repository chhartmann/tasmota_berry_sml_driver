import string
import json

class SmlSerial
  var read_buf
  var read_index
  var ser

  def init()
    self.read_buf = bytes()
    self.ser = serial(5, 17, 9600, serial.SERIAL_8N1)
    self.read_index = 0
  end

  def reset()
    self.read_buf.clear()
    self.ser.flush()
    self.read_index = 0
  end

  def read_data()
    if (self.ser.available() > 0)
      self.read_buf += self.ser.read()
      return true
    end
    return false
  end

  def dump_read(msg)
    # if (msg)
    #   print("SML: dump (" + msg + "): " + self.read_buf[0..self.read_index-1].tohex())
    # end
    self.read_buf = self.read_buf[self.read_index..]
    self.read_index = 0
  end

  def inc_index(val)
    var cur_index = self.read_index
    self.read_index += val
    return cur_index
  end
  
  def begins_with(d)
    var seq = bytes().fromhex(d)
    return (self.read_buf[0..size(seq)-1] == seq)
  end

  def parse_get_val()
    var tl = self.read_buf[self.inc_index(1)]
    var val = tl
    var tl_len = (val & 0x0F)
    var tl_type = (val & 0x70)

    # for larger values there is a second tl field
    if (tl & 0x80)
        tl_len = (tl_len * 16 + self.read_buf[self.inc_index(1)]) - 1 # subtract second tl byte
    end
    tl_len -= 1 # subtract tl byte

    #TODO: throw/catch exception and stop parsing in this case?
    if (tl_len < 0)
      print("SML: Something went wrong, len < 0...")
      return 0
    end

    if (tl_type == 0x70)
      return 0 # ignore list field
    end
    
    if (tl_type == 0x50 || tl_type == 0x60)
      if (tl_len <= 4)
        if (tl_type == 0x50)
          val = self.read_buf.geti(self.read_index, -tl_len)
        else
          val = self.read_buf.get(self.read_index, -tl_len)
        end
      else
        assert(tl_len == 8)
        val = int64()
        val.frombytes(self.read_buf[self.read_index..self.read_index+7].reverse(), 0)
      end
      self.inc_index(tl_len)
    else # type not supported      
      self.inc_index(tl_len)
      val = 0
    end
    return val
  end
end

class Smartmeter
  var sml_buf
  var state
  var values
  var trigger_count
  static var units = {0x1B : "W", 0x1D : "var", 0x1E : "Wh", 0x20 : "varh", 0x21 : "A", 0x23 : "V", 0x2C : "Hz" }

  def init()
    self.state = 0
    self.sml_buf = SmlSerial()
    self.values = {}
    self.trigger_count = 0
  end

  def every_second()
    self.trigger_count += 1
    if (self.trigger_count % 30 == 0)
        self.values = {}
        self.parse_sml()
        self.trigger_count = 0
    end
  end

  def web_sensor()
    tasmota.web_send("<table border=\"1\"><tr><th>Datapoint</th><th>Value</th><th>Scaler</th></tr>");
    for k : self.values.keys()
      tasmota.web_send(f"<tr><td>{k}</td><td>{self.values[k]['value']} {self.values[k]['unit']}</td><td>{self.values[k]['scaler']}</td></tr>"); 
    end
    tasmota.web_send("</table>");
  end

  #TODO: sometimes buffer is discarded, which includes start sequence
  def parse_start_symbol()
    assert(self.state == 0)
    if (self.sml_buf.begins_with("1B1B1B1B01010101"))
      self.sml_buf.inc_index(8)
      self.sml_buf.dump_read("start_sequence")
      self.state = 1
    else
      self.sml_buf.inc_index(1)
      self.sml_buf.dump_read()
    end
  end

  def parse_values()
    if (self.sml_buf.begins_with("7707"))
      var obis_code = self.sml_buf.read_buf[2..7]
      self.sml_buf.inc_index(8)
      self.sml_buf.parse_get_val() # ignore status
      self.sml_buf.parse_get_val() # ignore time
      var unit = self.units.find(self.sml_buf.parse_get_val())
      var scaler = self.sml_buf.parse_get_val()
      var value = self.sml_buf.parse_get_val()
      self.sml_buf.parse_get_val() # ignore signature
      if (unit)
        var obis_str = string.format("%d-%d:%d.%d.%d*%d", obis_code[0], obis_code[1], obis_code[2], obis_code[3], obis_code[4], obis_code[5])
        self.values[obis_str] = {'value':value, 'unit':unit, 'scaler':scaler}
      end
      self.sml_buf.dump_read("obis")
    elif (self.sml_buf.begins_with("00")) # fill byte
      self.sml_buf.inc_index(1)
      self.sml_buf.dump_read("ignored")
    elif (self.sml_buf.begins_with("1B1B1B1B")) # end sequence
      #TODO: verify CRC before publishing?
      tasmota.publish_result(json.dump(self.values), "data")
      self.sml_buf.inc_index(4)
      self.sml_buf.dump_read("end_sequence")
      self.state = 2
    else
      self.sml_buf.parse_get_val() # ignore data
      self.sml_buf.dump_read("ignored")
    end
  end

  def parse_sml()
    print("SML: Start reading")
    self.sml_buf.reset()
    self.state = 0

    var wait_count = 0
    while (wait_count < 50)
      if (self.sml_buf.read_buf.size() < 100)
        if (!self.sml_buf.read_data())
          tasmota.delay(50)
          wait_count += 1
        end
        continue
      end        

      if (self.state == 0)
        while ((self.state == 0) && (self.sml_buf.read_buf.size() >= 8))
          self.parse_start_symbol()
        end
      elif (self.state == 1)
        self.parse_values()
      else # state == 2 => end symbol detected
        assert(self.state == 2)
        print("SML: Finished parsing")
        return
      end
    end
    print("SML: Timeout parsing")
    print("SML: Discarding buffer: " + self.sml_buf.read_buf.tohex())
  end
end
  
smartMeterDrv = Smartmeter()
tasmota.add_driver(smartMeterDrv)