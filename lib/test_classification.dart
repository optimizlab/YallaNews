import 'services/news_intelligence.dart';

void main() {
  // Test Arabic sports classification
  var result1 = NewsIntelligence.extract("مباراة كرة قدم مثيرة بين فريقين كبيرين", "", "");
  print("Arabic Sports: ${result1.category}");
  
  // Test English sports classification
  var result2 = NewsIntelligence.extract("Exciting football match between two top teams", "", "");
  print("English Sports: ${result2.category}");
  
  // Test Arabic politics classification
  var result3 = NewsIntelligence.extract("الانتخابات الرئاسية تشهد إقبالاً كبيراً من الناخبين", "", "");
  print("Arabic Politics: ${result3.category}");
  
  // Test English politics classification
  var result4 = NewsIntelligence.extract("Presidential elections see high voter turnout", "", "");
  print("English Politics: ${result4.category}");
  
  // Test Arabic technology classification
  var result5 = NewsIntelligence.extract("هاتف ذكي جديد بميزات ثورية يتم إطلاقه في السوق", "", "");
  print("Arabic Technology: ${result5.category}");
  
  // Test English technology classification
  var result6 = NewsIntelligence.extract("New smartphone with revolutionary features launched in market", "", "");
  print("English Technology: ${result6.category}");
  
  // Test Arabic health classification
  var result7 = NewsIntelligence.extract("دراسة طبية تكتشف علاجاً فعالاً لمرض خطير", "", "");
  print("Arabic Health: ${result7.category}");
  
  // Test English health classification
  var result8 = NewsIntelligence.extract("Medical study discovers effective treatment for serious disease", "", "");
  print("English Health: ${result8.category}");
  
  // Test event type detection
  var event1 = NewsIntelligence.extract("حرب مستمرة في المنطقة تسبب في تدمير الممتلكات", "", "");
  print("Arabic Event Type: ${event1.eventType}");
  
  var event2 = NewsIntelligence.extract("Ongoing war in the region causes destruction of property", "", "");
  print("English Event Type: ${event2.eventType}");
  
  // Test subcategory detection
  var sub1 = NewsIntelligence.extract("مباراة كرة قدم مثيرة في الدوري المحلي", "", "");
  print("Arabic Subcategory: ${sub1.subcategory}");
  
  var sub2 = NewsIntelligence.extract("Exciting football match in the local league", "", "");
  print("English Subcategory: ${sub2.subcategory}");
}