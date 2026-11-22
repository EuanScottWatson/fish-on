import React, {useEffect, useState} from 'react';
import {Pressable, ScrollView, Text, View} from 'react-native';
import {fishingSummary} from './stats';

/**
 * Show counts based on recorded data without assuming unlogged trip history.
 */
export default function Statistics({base, catches, api, styles, onBack}) {
  const [trips, setTrips] = useState(null);
  const [message, setMessage] = useState('Loading trips…');
  useEffect(()=>{let active=true;api(base,'/api/trips').then(rows=>{if(!Array.isArray(rows))throw Error('Unexpected response.');if(active){setTrips(rows);setMessage('')}}).catch(()=>{if(active){setTrips(null);setMessage('Trip counts need a connection and a server that supports trips.')}});return()=>{active=false}},[api,base]);
  const year=new Date().getFullYear(), summary=fishingSummary(catches,trips,year);
  const row=(label,value)=> <View key={label} style={{flexDirection:'row',justifyContent:'space-between',paddingVertical:16,borderBottomWidth:1,borderColor:'#dce5dc'}}><Text style={[styles.paragraph,{flex:1,marginRight:12}]}>{label}</Text><Text style={styles.cardTitle}>{value}</Text></View>;
  return <ScrollView contentContainerStyle={styles.content}><Pressable accessibilityRole="button" onPress={onBack}><Text style={styles.textLink}>‹ Back to your journal</Text></Pressable><Text style={styles.eyebrow}>YOUR FISHING</Text><Text style={styles.title}>Statistics</Text><Text style={styles.subtitle}>Counts from what you have recorded.</Text>
    {row('Catches',summary.catches)}{row('Different species names',summary.species)}{row(`Catches dated ${year}`,summary.caughtThisYear)}{row('Trips recorded',summary.trips==null?'—':summary.trips)}{row('Trips with linked catches',summary.tripsWithLinkedCatches==null?'—':summary.tripsWithLinkedCatches)}
    {!!message&&<Text style={styles.paragraph}>{message}</Text>}<Text style={styles.small}>Species are counted by the names saved in your journal. Older standalone catches are not automatically assigned to a trip. A trip with no linked catches is not necessarily an unsuccessful trip.</Text>
  </ScrollView>;
}
