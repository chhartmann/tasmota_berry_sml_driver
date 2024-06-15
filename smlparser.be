import strict
import string

var smlparser = module('smlparser')

class SmlParser
  var values
  var parse_buf
  static var units = {0x1B : "W", 0x1D : "var", 0x1E : "Wh", 0x20 : "varh", 0x21 : "A", 0x23 : "V", 0x2C : "Hz" }

  def init()
    self.values = {}
    self.parse_buf = bytes()
  end

  def pop_int(l)
    var r = 0
    if (l <= 4)
      r = self.parse_buf.geti(0, -l)
    else
      r = int64()
      r.frombytes(self.parse_buf[0..7].reverse(), 0)
    end
#    print("int: " + str(r) + " " + self.parse_buf[0..l-1].tohex())
    self.parse_buf = self.parse_buf[l..]
    return r
  end
  
  def pop_uint(l)
    var r = 0
    if (l <= 4)
      r = self.parse_buf.get(0, -l)
    else
      r = int64()
      r.frombytes(self.parse_buf[0..7].reverse(), 0)
    end
#    print("uint: " + str(r) + " " + self.parse_buf[0..l-1].tohex())
    self.parse_buf = self.parse_buf[l..]
    return r
  end

  def pop_ignore(l)
#    print("ignore: " + self.parse_buf[0..l-1].tohex())
    self.parse_buf = self.parse_buf[l..]
  end

  def starts_with(s)
    b = bytes(s)
    return b == self.parse_buf[0..b.size()-1]
  end

  def parse_get_val()
    var val = 0
    var tl = self.pop_uint(1)
    var tl_len = (tl & 0x0F)
    var tl_type = (tl & 0x70)

    if ((tl == 0) || (tl == 1)) 
#      print("can't get val from tl_len 0 or 1")
      return 0
    end

    # for larger values there is a second tl field
    if (tl & 0x80)
        tl_len = tl_len * 16 + self.pop_uint(1)
        tl_len -= 1
    end
    tl_len -= 1 # subtract tl byte

    if (tl_type == 0x70)
#      print("ignoring list field")
      return 0 # ignore list field
    end

#    print("type 0x" + string.hex(tl_type) + " len " + str(tl_len))
    
    if (tl_type == 0x60)
      val = self.pop_uint(tl_len)
    elif (tl_type == 0x50)
      val = self.pop_int(tl_len)
    else # type not supported
#      print("ignoring unknown type")
      self.pop_ignore(tl_len)
      val = 0
    end
    return val
  end

  def extract_telegram()
    var start_seq = bytes("1B1B1B1B01010101")
    var stop_seq = bytes("1B1B1B1B")
    var success = false
    for i : 0..self.parse_buf.size()-size(start_seq)-1
      if (self.parse_buf[i..i+size(start_seq)-1] == start_seq)
        self.parse_buf = self.parse_buf[i..]
        success = true
        break
      end
    end
    for i : size(start_seq)..self.parse_buf.size()-4
      if (self.parse_buf[i..i+size(stop_seq)-1] == stop_seq)
        self.parse_buf = self.parse_buf[0..i+size(stop_seq)+3]
        success = success && true
        break
      end
    end
    return success
  end

  def verify_crc()
    var poly=0x8408
    var data = self.parse_buf[0..-3]
    var crc = 0xFFFF
    for bi : 0..data.size()-1
      var b = data.get(bi,1)
      var cur_byte = b
      for i : 0..7
        if (crc & 0x0001) ^ (cur_byte & 0x0001)
          crc = (crc >> 1) ^ poly
        else
          crc >>= 1
        end
        cur_byte >>= 1
      end
#      print("byte " + string.hex(b) + " " + string.hex(crc & 0xFFFF))
    end
    crc = (~crc & 0xFFFF)
    crc = (crc << 8) | ((crc >> 8) & 0xFF)
    return string.hex(crc & 0xFFFF) == self.parse_buf[-2..-1].tohex()
  end

  def parse_telegram()
    self.pop_ignore(8) # discard start symbol
    while (true)
      if (self.starts_with("7707"))
        var obis_code = self.parse_buf[2..7]
        self.pop_ignore(8)
        self.parse_get_val() # ignore status
        self.parse_get_val() # ignore time
        var unit = self.units.find(self.parse_get_val())
        var scaler = self.parse_get_val()
        var value = self.parse_get_val()        
        self.parse_get_val() # ignore signature
        if (unit)
          var obis_str = string.format("%d-%d:%d.%d.%d*%d", obis_code[0], obis_code[1], obis_code[2], obis_code[3], obis_code[4], obis_code[5])
          self.values[obis_str] = {'value':value, 'unit':unit, 'scaler':scaler}
        end
      elif (self.starts_with("1B1B1B1B")) # end sequence
        break
      else
        self.parse_get_val() # ignore data
      end
    end
  end

  def parse(data)
    self.parse_buf = data
    self.values = {}
    if (self.extract_telegram() && self.verify_crc())
      self.parse_telegram()
      return true
    else
      return false
    end
  end
end

smlparser.SmlParser = SmlParser
return smlparser
