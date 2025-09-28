# Jelo-Mu Desktop client

Due to .net MAUI not yet supported natively in Linux, using the WinFormsBlazor
solution. Enabling to create a desktop client on both Linux and Windows in theory.

## First use case: As an Admin, keep track of all the core services in form of a dashboard.

1) List the core services: display heartbeat status a - just a basic view.
   
 | EndPoint               | Heartbeat status           |
 |------------------------|----------------------------|
 | db:/vendor@fqdn:PORT   | Online|Maintenance|Offline |
 | faas:/vendor@fqdn:PORT |                            |                                                                                                                                                                                            
 | etc...                 |                            |

2) The operator may want to refresh the view more or less frequently than first milestone.
  - Enable refresh rate configuration
  - Apply subscription rate
  - Jelo, Copper, Silver, Electrum, Gold, Platinum and Mu

