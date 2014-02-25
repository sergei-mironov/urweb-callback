
fun main {} : transaction page = template (
  f <- form {};
  return 
    <xml>
      Welcome
      <hr/>
      {f}
    </xml>)
  
